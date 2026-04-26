FROM python:3.11-slim

WORKDIR /app

# Non-root user for least-privilege execution
RUN groupadd --gid 1001 appuser && \
    useradd  --uid 1001 --gid appuser --shell /bin/bash --create-home appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY evaluator.py agent.py ./

USER appuser

EXPOSE 8080

CMD ["uvicorn", "agent:app", "--host", "0.0.0.0", "--port", "8080"]
