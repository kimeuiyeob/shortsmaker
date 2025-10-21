from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from youtube_transcript_api import YouTubeTranscriptApi
from langchain_openai import ChatOpenAI
import re
import json

# FastAPI 앱 생성
app = FastAPI(
    title="YouTube 쇼츠 생성",
    description="YouTube 비디오 링크로 쇼츠 생성",
)

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 요청 데이터 모델
class VideoRequest(BaseModel):
    video_url: str
    api_key: str
    style: str = "감성적" # 기본값:D 감성적, 다른 옵션: 유머러스, 몰입형, 다큐멘터리

# 응답 데이터 모델
class ShortsScriptResponse(BaseModel):
    title: str
    subtitles: str
    narration: str
    visual_suggestions: str

def get_video_id(url):
    """YouTube URL에서 비디오 ID 추출"""
    patterns = [
        r'(?:v=|\/)([0-9A-Za-z_-]{11}).*',
        r'(?:embed\/)([0-9A-Za-z_-]{11})',
        r'^([0-9A-Za-z_-]{11})$'
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    return None

def download_transcript(video_url, language='ko'):
    """YouTube 비디오 자막 다운로드"""
    try:
        video_id = get_video_id(video_url)
        if not video_id:
            raise ValueError("유효하지 않은 YouTube URL입니다.")
        
        ytt_api = YouTubeTranscriptApi()
        
        try:
            fetched_transcript = ytt_api.fetch(video_id, languages=[language])
        except:
            try:
                fetched_transcript = ytt_api.fetch(video_id, languages=['en'])
            except:
                fetched_transcript = ytt_api.fetch(video_id)
        
        transcript_data = fetched_transcript.to_raw_data()
        full_text = '\n'.join([item['text'] for item in transcript_data])
        
        return full_text
    except Exception as e:
        raise Exception(f"자막 다운로드 실패: {str(e)}")

def generate_shorts_script(transcript_text, api_key, style="감성적"):
    """GPT를 사용하여 쇼츠 스크립트 생성"""
    try:
        if not api_key:
            raise ValueError("OpenAI API 키가 필요합니다.")
      
        model = ChatOpenAI(model="gpt-4o-mini", openai_api_key=api_key, temperature=0.3)
        
        prompt = f"""You are an expert scriptwriter for short-form video content. Your task is to create a YouTube Shorts script based on the provided YouTube video transcript. The script must include a catchy title, engaging subtitles, narration, and visual suggestions, tailored to a specific style.

**Input:**
- Transcript: {transcript_text}
- Desired Style: {style}
- Duration: 1 minute

**Instructions:**

1. **Summary Requirements:**
   - Extract only the core message and key information from the transcript.
   - Maintain logical flow and coherence.
   - Avoid omitting critical information.

2. **Style Requirements:**
   - Adapt the tone and language to match the specified style ({style}).
   - For example:
     - Emotional: Use heartfelt, inspiring language to evoke deep feelings.
     - Funny: Incorporate humor, light-hearted phrasing, or witty remarks.
     - Immersive: Create vivid, sensory-driven descriptions to captivate the audience.
     - Documentary : Use factual, authoritative, and narrative-driven language.

3. **Output Format:**
   - **Title**: A short, attention-grabbing title (5-10 words) that hooks the audience.
   - **Subtitles**: Concise, engaging text for on-screen display
   - **Narration**: A script for voice-over that matches the style and complements the subtitles
   - **Visual Suggestions**: Brief descriptions of visuals or effects to enhance the narrative

4. **Language**: Write the title, subtitles, and narration in Korean. Visual suggestions can be in English for clarity.

**Output:**
Provide the response in JSON format with the structure:
```json
{{
  "title": "한국어로 된 후킹 제목",
  "subtitles": "간결하고 매력적인 자막 텍스트",
  "narration": "내레이션 스크립트",
  "visual_suggestions": "Visual descriptions"
}}
```

Important: Respond ONLY with valid JSON. Do not include any text before or after the JSON."""

        response = model.invoke(prompt)
        content = response.content.strip()
        
        # JSON 추출 (마크다운 코드 블록 제거)
        if content.startswith("```"):
            content = content.split("```")[1]
            if content.startswith("json"):
                content = content[4:]
            content = content.strip()
        
        # JSON 파싱
        result = json.loads(content)
        
        return result
    
    except json.JSONDecodeError as e:
        raise Exception(f"JSON 파싱 실패: {str(e)}\n응답 내용: {content}")
    except Exception as e:
        raise Exception(f"스크립트 생성 실패: {str(e)}")


@app.post("/summarize", response_model=ShortsScriptResponse)
async def generate_shorts(request: VideoRequest):
    """
    YouTube 비디오를 1분 쇼츠 스크립트로 변환합니다.
    
    Request Body:
    - video_url: YouTube 비디오 URL
    - api_key: OpenAI API Key
    - style: 스타일 (감성적, 유머러스, 몰입형, 다큐멘터리)
    
    Response:
    - title: 제목
    - subtitles: 자막
    - narration: 내레이션
    - visual_suggestions: 비주얼 제안
    """
    try:
        # 1. 자막 다운로드
        transcript_text = download_transcript(request.video_url, language='ko')
        
        # 2. GPT로 쇼츠 스크립트 생성
        script = generate_shorts_script(
            transcript_text,
            request.api_key,
            request.style
        )
        
        # 3. 결과 반환
        return ShortsScriptResponse(
            title=script["title"],
            subtitles=script["subtitles"],
            narration=script["narration"],
            visual_suggestions=script["visual_suggestions"]
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/")
async def root():
    """API 상태 확인"""
    return {
        "message": "YouTube 쇼츠 스크립트 생성 API",
        "endpoints": {
            "/summary": "POST - 쇼츠 스크립트 생성",
            "/docs": "API 문서"
        },
        "available_styles": ["감성적", "유머러스", "몰입형", "다큐멘터리"]
    }

# 서버 실행
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
