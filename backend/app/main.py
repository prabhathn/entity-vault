from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import resolve, encode, transcode, enrich, entities, namespaces, audit, demo, contributions

app = FastAPI(
    title="Entity Vault API",
    description="Identity Resolution, Encoding, Transcoding, and Enrichment Platform",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(resolve.router)
app.include_router(encode.router)
app.include_router(transcode.router)
app.include_router(enrich.router)
app.include_router(entities.router)
app.include_router(namespaces.router)
app.include_router(audit.router)
app.include_router(demo.router)
app.include_router(contributions.router)


@app.get("/")
def root():
    return {"service": "Entity Vault", "version": "1.0.0", "status": "operational"}


@app.get("/api/health")
def health():
    return {"status": "healthy"}
