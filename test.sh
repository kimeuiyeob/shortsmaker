#!/bin/bash

# Configuration
CONFIG_FILE="$(dirname "$0")/.config"
API_URL="http://localhost:8000"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Function to validate YouTube URL
validate_youtube_url() {
    local url=$1
    if [[ $url =~ ^(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/)[a-zA-Z0-9_-]{11} ]]; then
        return 0
    else
        return 1
    fi
}

# Function to load API key from config
load_api_key() {
    if [ -f "${CONFIG_FILE}" ]; then
        source "${CONFIG_FILE}"
        if [ -n "${GPT_API_KEY}" ]; then
            print_success "API key loaded from config file"
            return 0
        fi
    fi
    return 1
}

# Function to save API key to config
save_api_key() {
    local key=$1
    echo "GPT_API_KEY=\"${key}\"" > "${CONFIG_FILE}"
    chmod 600 "${CONFIG_FILE}"
    print_success "API key saved to ${CONFIG_FILE}"
}

# Function to get API key
get_api_key() {
    if load_api_key; then
        return 0
    fi
    
    echo ""
    print_info "API key not found in config file"
    read -p "Enter your GPT API key: " -s api_key
    echo ""
    
    if [ -z "${api_key}" ]; then
        print_error "API key cannot be empty"
        exit 1
    fi
    
    GPT_API_KEY="${api_key}"
    
    read -p "Save API key for future use? (y/n): " save_choice
    if [[ $save_choice =~ ^[Yy]$ ]]; then
        save_api_key "${api_key}"
    fi
}

# Function to select style
select_style() {
    echo ""
    print_info "Select narration style:"
    echo "  1) Emotional"
    echo "  2) Funny"
    echo "  3) Immersive"
    echo "  4) Documentary"
    echo ""
    
    while true; do
        read -p "Choose style [1-4] (default: 3): " style_choice
        
        # Default to Immersive if empty
        style_choice=${style_choice:-3}
        
        case $style_choice in
            1)
                STYLE="Emotional"
                break
                ;;
            2)
                STYLE="Funny"
                break
                ;;
            3)
                STYLE="Immersive"
                break
                ;;
            4)
                STYLE="Documentary"
                break
                ;;
            *)
                print_error "Invalid choice. Please select 1-4"
                ;;
        esac
    done
    
    print_success "Selected style: ${STYLE}"
}

# Function to get YouTube URL
get_youtube_url() {
    echo ""
    print_info "Enter YouTube URL"
    echo "Examples:"
    echo "  • https://www.youtube.com/watch?v=21U7CMt9sdk"
    echo "  • https://youtu.be/21U7CMt9sdk"
    echo ""
    
    while true; do
        read -p "YouTube URL: " youtube_url
        
        if [ -z "${youtube_url}" ]; then
            print_error "URL cannot be empty"
            continue
        fi
        
        if validate_youtube_url "${youtube_url}"; then
            YOUTUBE_URL="${youtube_url}"
            print_success "Valid YouTube URL"
            break
        else
            print_error "Invalid YouTube URL format"
            echo "Please enter a valid YouTube URL"
        fi
    done
}

# Function to show summary and confirm
show_summary() {
    echo ""
    echo "=========================================="
    print_info "Request Summary"
    echo "=========================================="
    echo "API URL     : ${API_URL}"
    echo "YouTube URL : ${YOUTUBE_URL}"
    echo "Style       : ${STYLE}"
    echo "=========================================="
    echo ""
    
    read -p "Proceed with this request? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_warning "Request cancelled"
        exit 0
    fi
}

# Function to make API request
make_request() {
    echo ""
    print_info "Sending request to API..."
    echo ""
    
    local response
    local http_code
    
    # Make the request and capture both response and HTTP code
    response=$(curl -w "\n%{http_code}" -X POST "${API_URL}/summarize" \
        -H "Content-Type: application/json" \
        -d "{
            \"video_url\": \"${YOUTUBE_URL}\",
            \"api_key\": \"${GPT_API_KEY}\",
            \"style\": \"${STYLE}\"
        }" 2>&1)
    
    # Extract HTTP code (last line)
    http_code=$(echo "$response" | tail -n1)
    # Extract response body (all but last line)
    response_body=$(echo "$response" | sed '$d')
    
    echo ""
    
    if [ "$http_code" -eq 200 ]; then
        print_success "Request successful!"
        echo ""
        echo "Response:"
        echo "${response_body}" | jq '.' 2>/dev/null || echo "${response_body}"
    else
        print_error "Request failed (HTTP ${http_code})"
        echo ""
        echo "Response:"
        echo "${response_body}" | jq '.' 2>/dev/null || echo "${response_body}"
        exit 1
    fi
}

# Function to check if API is running
check_api() {
    print_info "Checking API availability..."
    
    if curl -s -f "${API_URL}/health" > /dev/null 2>&1 || \
       curl -s -f "${API_URL}/" > /dev/null 2>&1; then
        print_success "API is running"
        return 0
    else
        print_error "API is not accessible at ${API_URL}"
        echo ""
        echo "Please ensure:"
        echo "  1. The API server is running"
        echo "  2. The API URL is correct"
        echo "  3. There are no firewall issues"
        exit 1
    fi
}

# Main execution
main() {
    echo ""
    echo "=========================================="
    echo "  YouTube Video Summarizer"
    echo "=========================================="
    
    # Check if running in non-interactive mode (with arguments)
    if [ $# -eq 1 ]; then
        YOUTUBE_URL=$1
        if ! validate_youtube_url "${YOUTUBE_URL}"; then
            print_error "Invalid YouTube URL: ${YOUTUBE_URL}"
            exit 1
        fi
        get_api_key
        STYLE="Immersive"  # Default style for non-interactive mode
        check_api
        make_request
        exit 0
    elif [ $# -eq 2 ]; then
        YOUTUBE_URL=$1
        STYLE=$2
        if ! validate_youtube_url "${YOUTUBE_URL}"; then
            print_error "Invalid YouTube URL: ${YOUTUBE_URL}"
            exit 1
        fi
        get_api_key
        check_api
        make_request
        exit 0
    fi
    
    # Interactive mode
    check_api
    get_api_key
    get_youtube_url
    select_style
    show_summary
    make_request
    
    echo ""
    print_success "Done!"
}

# Show usage
usage() {
    echo "Usage: $0 [YOUTUBE_URL] [STYLE]"
    echo ""
    echo "Interactive mode:"
    echo "  $0"
    echo ""
    echo "Non-interactive mode:"
    echo "  $0 <youtube_url>"
    echo "  $0 <youtube_url> <style>"
    echo ""
    echo "Styles: Emotional, Funny, Immersive, Documentary"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 https://www.youtube.com/watch?v=21U7CMt9sdk"
    echo "  $0 https://www.youtube.com/watch?v=21U7CMt9sdk Funny"
    exit 0
}

# Parse arguments
case "${1:-}" in
    -h|--help)
        usage
        ;;
    *)
        main "$@"
        ;;
esac
