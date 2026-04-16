# Solace-AI: GraphRAG Final Reconciled Dockerfile
# Optimized for Python 3.12 / Podman / macOS Volume Permissions (2026)
FROM python:3.12-slim

# 1. Install uv for lightning-fast installs (2026 standard)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set environment variables for container stability
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PIP_DEFAULT_TIMEOUT=1000 \
    PIP_RETRIES=10 \
    POETRY_DYNAMIC_VERSIONING_BYPASS="0.0.0"

WORKDIR /app

# 2. Install system dependencies required for GraphRAG and Git builds
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl git ffmpeg && rm -rf /var/lib/apt/lists/*

# 3. Install stable background dependencies using uv
# Pinned versions preserved exactly from your original requirement
RUN uv pip install --system --no-cache-dir \
    gradio==4.44.1 \
    huggingface_hub==0.23.4 \
    pydantic==2.7.4 \
    jinja2==3.1.4 \
    starlette==0.38.2 \
    fastapi \
    uvicorn \
    python-dotenv \
    pandas \
    tiktoken \
    langchain==0.2.16 \
    langchain-community==0.2.16 \
    langchain-core==0.2.38 \
    aiohttp \
    pyyaml \
    requests \
    duckduckgo-search \
    ollama \
    plotly

# 4. Install GraphRAG separately (v0.1.1)
RUN uv pip install --system --no-cache-dir \
    git+https://github.com/microsoft/graphrag.git@v0.1.1

# 5. THE PATH FIX: Copy everything from the current directory
COPY . .

# 6. THE SURGICAL FIXES (All Original Functionality Preserved + Critical Fixes)
# A. Revert import path for v0.1.1 compatibility
RUN sed -i 's/graphrag.query.llm.text_utils/graphrag.query.context_builder.entity_extraction/g' api.py

# B. Force FastAPI and Gradio to bind to 0.0.0.0
RUN sed -i 's/127.0.0.1/0.0.0.0/g' api.py app.py index_app.py

# C. Update Ollama hostname to host.docker.internal for Mac GPU bridge
RUN sed -i 's/localhost:11434/host.docker.internal:11434/g' app.py index_app.py api.py

# D. Dynamic pathing for the Gradio client patch
RUN sed -i 's/def _json_schema_to_python_type(schema, defs):/def _json_schema_to_python_type(schema, defs):\n    if isinstance(schema, bool):\n        return "Any"/g' $(python -c "import site; print(site.getsitepackages()[0])")/gradio_client/utils.py

# E. UI PATH DISCOVERY FIX: Hard-code root to /app to resolve "No folder selected"
RUN sed -i "s|root_dir = os.path.dirname(os.path.abspath(__file__))|root_dir = '/app'|g" app.py

# F. INTERNAL NETWORKING FIX: Force the Indexer to talk to the API container
# This stops the "Connection refused" error when indexer tries to find localhost
RUN sed -i "s|localhost:8012|graphrag-api:8012|g" index_app.py || true

# 7. Setup persistent directories and wipe "ghost" build artifacts
RUN mkdir -p indexing lancedb input cache output
RUN chmod -R 777 /app

# 8. PERMISSION FIX: Run as root for Podman/macOS Volume compatibility
# This ensures that the Indexer can write .tmp files and parquet files to your Mac
USER root

# Expose ports: API (8012), Chat UI (7860), Indexer (7861)
EXPOSE 8012 7860 7861

# 9. Start the API
CMD ["python", "api.py", "--host", "0.0.0.0", "--port", "8012"]