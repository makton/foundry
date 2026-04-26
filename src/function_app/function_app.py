import json
import logging

import azure.functions as func

from eval_trigger import bp as eval_bp
from url_processor import URLProcessor

logger = logging.getLogger(__name__)
app = func.FunctionApp()
app.register_functions(eval_bp)   # eval-jobs QueueTrigger

_processor = URLProcessor()


# ── Timer trigger: process all pending URLs every 6 hours ─────────────────────

@app.timer_trigger(
    schedule="0 0 */6 * * *",
    arg_name="timer",
    run_on_startup=False,
    use_monitor=True,
)
async def process_urls_timer(timer: func.TimerRequest) -> None:
    if timer.past_due:
        logger.warning("Timer trigger is past due — running now")
    logger.info("Starting scheduled URL processing run")
    await _processor.process_pending()
    logger.info("Scheduled URL processing run complete")


# ── HTTP triggers: URL management admin API ───────────────────────────────────

@app.route(route="urls", methods=["GET"], auth_level=func.AuthLevel.FUNCTION)
async def list_urls(req: func.HttpRequest) -> func.HttpResponse:
    try:
        items = await _processor.list_urls()
        return _json_ok(items)
    except Exception:
        logger.exception("list_urls failed")
        return _error(500, "Failed to list URLs")


@app.route(route="urls", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
async def add_url(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except ValueError:
        return _error(400, "Request body must be valid JSON")

    url = (body.get("url") or "").strip()
    if not url:
        return _error(400, "Missing required field: url")

    try:
        doc = await _processor.add_url(url)
        return _json_ok(doc, status_code=202)
    except ValueError as exc:
        return _error(400, str(exc))
    except Exception:
        logger.exception("add_url failed url=%s", url)
        return _error(500, "Failed to add URL")


@app.route(route="urls/{url_id}", methods=["DELETE"], auth_level=func.AuthLevel.FUNCTION)
async def delete_url(req: func.HttpRequest) -> func.HttpResponse:
    url_id = req.route_params.get("url_id", "").strip()
    if not url_id:
        return _error(400, "Missing url_id in path")

    try:
        await _processor.delete_url(url_id)
        return func.HttpResponse(status_code=204)
    except Exception:
        logger.exception("delete_url failed url_id=%s", url_id)
        return _error(500, "Failed to delete URL")


@app.route(route="urls/{url_id}/reprocess", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
async def reprocess_url(req: func.HttpRequest) -> func.HttpResponse:
    url_id = req.route_params.get("url_id", "").strip()
    if not url_id:
        return _error(400, "Missing url_id in path")

    try:
        await _processor.reprocess_url(url_id)
        return _json_ok({"status": "queued", "url_id": url_id}, status_code=202)
    except Exception:
        logger.exception("reprocess_url failed url_id=%s", url_id)
        return _error(500, "Failed to queue URL for reprocessing")


# ── Helpers ───────────────────────────────────────────────────────────────────

def _json_ok(data, status_code: int = 200) -> func.HttpResponse:
    return func.HttpResponse(
        body=json.dumps(data),
        status_code=status_code,
        mimetype="application/json",
    )


def _error(status_code: int, message: str) -> func.HttpResponse:
    return func.HttpResponse(
        body=json.dumps({"error": message}),
        status_code=status_code,
        mimetype="application/json",
    )
