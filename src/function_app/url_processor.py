import hashlib
import logging
import os
import re
from datetime import datetime, timezone
from io import BytesIO
from typing import Optional
from urllib.parse import urlparse

import httpx
import tiktoken
from azure.cosmos.aio import CosmosClient
from azure.identity.aio import ManagedIdentityCredential
from azure.search.documents.aio import SearchClient
from azure.search.documents.indexes.aio import SearchIndexClient
from azure.search.documents.indexes.models import (
    HnswAlgorithmConfiguration,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
    SimpleField,
    VectorSearch,
    VectorSearchProfile,
)
from bs4 import BeautifulSoup
from openai import AsyncAzureOpenAI
from pypdf import PdfReader

logger = logging.getLogger(__name__)

_CHUNK_TOKENS = 500
_CHUNK_OVERLAP = 50
_EMBED_DIMENSIONS = 1536
_MAX_DOWNLOAD_BYTES = 10 * 1024 * 1024  # 10 MB
_DOWNLOAD_TIMEOUT = 30.0
_EMBED_BATCH_SIZE = 16

_TAGS_TO_REMOVE = [
    "script", "style", "nav", "footer", "header",
    "aside", "form", "noscript", "iframe",
]


def _url_id(url: str) -> str:
    return hashlib.sha256(url.encode()).hexdigest()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class URLProcessor:
    def __init__(self) -> None:
        client_id = os.environ["AZURE_CLIENT_ID"]
        self._credential = ManagedIdentityCredential(client_id=client_id)

        self._cosmos = CosmosClient(
            os.environ["COSMOSDB_ENDPOINT"], credential=self._credential
        )
        self._db_name = os.environ["COSMOSDB_DATABASE_NAME"]
        self._urls_container = os.environ["COSMOSDB_URLS_CONTAINER"]
        self._docs_container = os.environ["COSMOSDB_DOCUMENTS_CONTAINER"]
        self._chunks_container = os.environ["COSMOSDB_CHUNKS_CONTAINER"]
        self._status_container = os.environ["COSMOSDB_STATUS_CONTAINER"]

        self._openai = AsyncAzureOpenAI(
            azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
            azure_ad_token_provider=self._token_provider,
            api_version="2024-10-21",
        )
        self._embedding_deployment = os.environ["AZURE_OPENAI_EMBEDDING_DEPLOYMENT"]

        search_endpoint = os.environ.get("AZURE_AI_SEARCH_ENDPOINT", "")
        self._search_index_name = os.environ.get("AZURE_AI_SEARCH_INDEX_NAME", "foundry-chunks")
        self._search_client: Optional[SearchClient] = None
        self._search_index_client: Optional[SearchIndexClient] = None
        if search_endpoint:
            self._search_client = SearchClient(
                endpoint=search_endpoint,
                index_name=self._search_index_name,
                credential=self._credential,
            )
            self._search_index_client = SearchIndexClient(
                endpoint=search_endpoint,
                credential=self._credential,
            )

        self._enc = tiktoken.get_encoding("cl100k_base")

    async def _token_provider(self) -> str:
        token = await self._credential.get_token("https://cognitiveservices.azure.com/.default")
        return token.token

    # ── Public API ────────────────────────────────────────────────────────────

    async def list_urls(self) -> list[dict]:
        db = self._cosmos.get_database_client(self._db_name)
        container = db.get_container_client(self._urls_container)
        items = []
        async for item in container.query_items(
            query="SELECT c.id, c.url, c.status, c.added_at, c.processed_at, c.error FROM c ORDER BY c.added_at DESC",
        ):
            items.append(item)
        return items

    async def add_url(self, url: str) -> dict:
        _validate_url(url)
        url_id = _url_id(url)
        db = self._cosmos.get_database_client(self._db_name)
        container = db.get_container_client(self._urls_container)
        doc = {
            "id": url_id,
            "url": url,
            "status": "pending",
            "added_at": _now(),
            "processed_at": None,
            "error": None,
        }
        await container.upsert_item(doc)
        return doc

    async def delete_url(self, url_id: str) -> None:
        db = self._cosmos.get_database_client(self._db_name)
        urls = db.get_container_client(self._urls_container)
        item = await urls.read_item(item=url_id, partition_key=url_id)
        url = item["url"]

        await urls.delete_item(item=url_id, partition_key=url_id)

        # Remove derived documents and chunks keyed by url_id
        for cname in (self._docs_container, self._chunks_container):
            c = db.get_container_client(cname)
            async for row in c.query_items(
                query="SELECT c.id FROM c WHERE c.url_id = @uid",
                parameters=[{"name": "@uid", "value": url_id}],
            ):
                await c.delete_item(item=row["id"], partition_key=url_id)

        # Remove status records
        sc = db.get_container_client(self._status_container)
        async for row in sc.query_items(
            query="SELECT c.id FROM c WHERE c.source_id = @uid",
            parameters=[{"name": "@uid", "value": url_id}],
        ):
            await sc.delete_item(item=row["id"], partition_key=row.get("status", "processing"))

        # Remove from AI Search
        if self._search_client:
            async with self._search_client:
                docs = [{"id": chunk_id} async for chunk_id in self._search_chunks_for_url(url_id)]
                if docs:
                    await self._search_client.delete_documents(documents=docs)

        logger.info("Deleted url_id=%s url=%s", url_id, url)

    async def reprocess_url(self, url_id: str) -> None:
        db = self._cosmos.get_database_client(self._db_name)
        container = db.get_container_client(self._urls_container)
        item = await container.read_item(item=url_id, partition_key=url_id)
        item["status"] = "pending"
        item["error"] = None
        await container.replace_item(item=url_id, body=item)

    async def process_pending(self) -> None:
        if self._search_index_client:
            await self._ensure_index()

        db = self._cosmos.get_database_client(self._db_name)
        container = db.get_container_client(self._urls_container)
        async for item in container.query_items(
            query="SELECT * FROM c WHERE c.status = 'pending'",
        ):
            url_id = item["id"]
            url = item["url"]
            logger.info("Processing url_id=%s url=%s", url_id, url)
            try:
                await self._process_one(db, item)
                item["status"] = "completed"
                item["processed_at"] = _now()
                item["error"] = None
            except Exception as exc:
                logger.exception("Failed url_id=%s", url_id)
                item["status"] = "failed"
                item["error"] = str(exc)[:500]
            await container.replace_item(item=url_id, body=item)

    # ── Pipeline internals ────────────────────────────────────────────────────

    async def _process_one(self, db, url_item: dict) -> None:
        url_id = url_item["id"]
        url = url_item["url"]

        raw, content_type = await _download(url)
        text = _extract_text(raw, content_type, url)
        if not text.strip():
            raise ValueError("No extractable text found at URL")

        chunks = _chunk_text(text, self._enc)
        logger.info("url_id=%s produced %d chunks", url_id, len(chunks))

        # Store source document
        docs_c = db.get_container_client(self._docs_container)
        source_doc = {
            "id": url_id,
            "url_id": url_id,
            "source": url,
            "content": text[:50_000],  # cap stored raw text
            "content_type": content_type,
            "chunk_count": len(chunks),
            "indexed_at": _now(),
        }
        await docs_c.upsert_item(source_doc)

        # Embed in batches
        all_embeddings = await self._embed_chunks(chunks)

        # Store chunks and index
        chunks_c = db.get_container_client(self._chunks_container)
        search_docs = []
        for i, (chunk, embedding) in enumerate(zip(chunks, all_embeddings)):
            chunk_id = f"{url_id}_{i:04d}"
            cosmos_chunk = {
                "id": chunk_id,
                "document_id": url_id,
                "url_id": url_id,
                "source": url,
                "chunk_index": i,
                "content": chunk,
                "embedding": embedding,
            }
            await chunks_c.upsert_item(cosmos_chunk)
            search_docs.append({
                "id": chunk_id,
                "url_id": url_id,
                "source": url,
                "chunk_index": i,
                "content": chunk,
                "content_vector": embedding,
            })

        if self._search_client and search_docs:
            async with self._search_client:
                await self._search_client.upload_documents(documents=search_docs)

        # Write processing status
        status_c = db.get_container_client(self._status_container)
        await status_c.upsert_item({
            "id": f"url-{url_id}",
            "source_id": url_id,
            "source_type": "url",
            "status": "completed",
            "chunk_count": len(chunks),
            "processed_at": _now(),
        })

    async def _embed_chunks(self, chunks: list[str]) -> list[list[float]]:
        results = []
        for i in range(0, len(chunks), _EMBED_BATCH_SIZE):
            batch = chunks[i : i + _EMBED_BATCH_SIZE]
            resp = await self._openai.embeddings.create(
                model=self._embedding_deployment,
                input=batch,
                dimensions=_EMBED_DIMENSIONS,
            )
            results.extend(e.embedding for e in resp.data)
        return results

    async def _search_chunks_for_url(self, url_id: str):
        async with self._search_client:
            results = await self._search_client.search(
                search_text="*",
                filter=f"url_id eq '{url_id}'",
                select=["id"],
                top=10_000,
            )
            async for r in results:
                yield r["id"]

    async def _ensure_index(self) -> None:
        index = SearchIndex(
            name=self._search_index_name,
            fields=[
                SimpleField(name="id", type=SearchFieldDataType.String, key=True, filterable=True),
                SimpleField(name="url_id", type=SearchFieldDataType.String, filterable=True),
                SimpleField(name="source", type=SearchFieldDataType.String, filterable=True, facetable=False),
                SimpleField(name="chunk_index", type=SearchFieldDataType.Int32, filterable=True, sortable=True),
                SearchField(
                    name="content",
                    type=SearchFieldDataType.String,
                    searchable=True,
                    analyzer_name="en.lucene",
                ),
                SearchField(
                    name="content_vector",
                    type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                    searchable=True,
                    vector_search_dimensions=_EMBED_DIMENSIONS,
                    vector_search_profile_name="hnsw-profile",
                ),
            ],
            vector_search=VectorSearch(
                algorithms=[HnswAlgorithmConfiguration(name="hnsw", parameters={"m": 4, "ef_construction": 400, "ef_search": 500, "metric": "cosine"})],
                profiles=[VectorSearchProfile(name="hnsw-profile", algorithm_configuration_name="hnsw")],
            ),
            semantic_search=SemanticSearch(
                configurations=[
                    SemanticConfiguration(
                        name="default",
                        prioritized_fields=SemanticPrioritizedFields(
                            content_fields=[SemanticField(field_name="content")],
                        ),
                    )
                ]
            ),
        )
        try:
            async with self._search_index_client:
                await self._search_index_client.create_or_update_index(index)
        except Exception:
            logger.exception("Failed to create/update search index")


# ── Pure helper functions ─────────────────────────────────────────────────────

def _validate_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError(f"URL must use http or https scheme: {url}")
    if not parsed.netloc:
        raise ValueError(f"URL has no hostname: {url}")
    # Block private/loopback ranges to prevent SSRF
    host = parsed.hostname or ""
    if _is_private_host(host):
        raise ValueError(f"URL resolves to a private/loopback address: {host}")


def _is_private_host(host: str) -> bool:
    private_patterns = [
        r"^localhost$",
        r"^127\.",
        r"^10\.",
        r"^172\.(1[6-9]|2\d|3[01])\.",
        r"^192\.168\.",
        r"^::1$",
        r"^fd[0-9a-f]{2}:",
        r"^169\.254\.",
        r"^0\.0\.0\.0$",
        r"^metadata\.google",
        r"^169\.254\.169\.254$",
    ]
    h = host.lower()
    return any(re.match(p, h) for p in private_patterns)


async def _download(url: str) -> tuple[bytes, str]:
    async with httpx.AsyncClient(
        follow_redirects=True,
        timeout=_DOWNLOAD_TIMEOUT,
        headers={"User-Agent": "FoundryBot/1.0 (+https://github.com/azure-ai-foundry)"},
    ) as client:
        async with client.stream("GET", url) as resp:
            resp.raise_for_status()
            content_type = resp.headers.get("content-type", "").split(";")[0].strip().lower()
            chunks = []
            total = 0
            async for chunk in resp.aiter_bytes(chunk_size=65536):
                total += len(chunk)
                if total > _MAX_DOWNLOAD_BYTES:
                    raise ValueError(f"Download exceeded {_MAX_DOWNLOAD_BYTES // 1024 // 1024} MB limit")
                chunks.append(chunk)
    return b"".join(chunks), content_type


def _extract_text(raw: bytes, content_type: str, url: str) -> str:
    if "pdf" in content_type or url.lower().endswith(".pdf"):
        return _extract_pdf(raw)
    return _extract_html(raw)


def _extract_html(raw: bytes) -> str:
    soup = BeautifulSoup(raw, "lxml")
    for tag in soup(_TAGS_TO_REMOVE):
        tag.decompose()
    # Prefer <main> or <article> content; fall back to <body>
    root = soup.find("main") or soup.find("article") or soup.find("body") or soup
    text = root.get_text(separator="\n")
    # Collapse runs of blank lines
    lines = [ln.strip() for ln in text.splitlines()]
    return "\n".join(ln for ln in lines if ln)


def _extract_pdf(raw: bytes) -> str:
    reader = PdfReader(BytesIO(raw))
    parts = []
    for page in reader.pages:
        text = page.extract_text() or ""
        if text.strip():
            parts.append(text)
    return "\n".join(parts)


def _chunk_text(text: str, enc: tiktoken.Encoding) -> list[str]:
    tokens = enc.encode(text)
    chunks = []
    start = 0
    while start < len(tokens):
        end = min(start + _CHUNK_TOKENS, len(tokens))
        chunk_tokens = tokens[start:end]
        chunks.append(enc.decode(chunk_tokens))
        if end == len(tokens):
            break
        start += _CHUNK_TOKENS - _CHUNK_OVERLAP
    return chunks
