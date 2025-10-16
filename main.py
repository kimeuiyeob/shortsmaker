from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from youtube_transcript_api import YouTubeTranscriptApi
from langchain_openai import ChatOpenAI
import re

# FastAPI 앱 생성
app = FastAPI(
    title="YouTube 요약 API",
    description="YouTube 비디오 자막을 다운로드하고 GPT로 요약하는 API",
    version="1.0.0"
)

# CORS 설정 (프론트엔드에서 접근 가능하도록)
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

# 응답 데이터 모델
class SummaryResponse(BaseModel):
    summary: str

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

def summarize_transcript_with_gpt(transcript_text, api_key, duration_minutes=1):
    """GPT를 사용하여 자막을 요약"""
    try:
        if not api_key:
            raise ValueError("OpenAI API 키가 필요합니다.")
        
        model = ChatOpenAI(model="gpt-4o-mini", openai_api_key=api_key, temperature=0.3)
        
        prompt = f"""이건 YouTube 비디오의 자막이야. 
        이 내용을 {duration_minutes}분 쇼츠 자막으로 만들어줘.
        항상 대답할때는 한국어로 대답해.
        요약 조건:
        - 핵심 내용만 추출
        - 논리적 흐름 유지
        - 중요한 정보 누락 없이
        - {duration_minutes}분 안에 읽을 수 있는 분량
        
        자막 내용: {transcript_text}
        
        요약:"""
        
        response = model.invoke(prompt)
        summary = response.content
        return summary
        
    except Exception as e:
        raise Exception(f"요약 생성 실패: {str(e)}")

# API 엔드포인트
@app.post("/summarize", response_model=SummaryResponse)
async def summarize_video(request: VideoRequest):
    """
    YouTube 비디오를 1분 쇼츠 자막으로 요약합니다.
    
    Request Body:
    - video_url: YouTube 비디오 URL
    - api_key: OpenAI API Key
    
    Response:
    - summary: 1분 분량의 요약 텍스트
    """
    try:
        # 1. 자막 다운로드
        transcript_text = download_transcript(request.video_url, language='ko')
        
        # 2. GPT로 요약 (1분 분량 고정)
        summary = summarize_transcript_with_gpt(
            transcript_text,
            request.api_key,
            duration_minutes=1
        )
        
        # 3. 요약 결과만 반환
        return SummaryResponse(summary=summary)
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 서버 실행
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

