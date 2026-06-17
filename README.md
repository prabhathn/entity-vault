# Entity Vault

A Snowflake-native identity resolution, encoding, and enrichment platform — similar in concept to LiveRamp and Datavant, but abstracted to work with any entity type (products, people, locations, or any other sensitive entity).

## What Does This Solve?

Organizations manage entities (customers, products, locations) across many systems and partners. Each partner uses different identifiers for the same entity, creating fragmentation and cross-partner correlation risks. Entity Vault provides:

- **A single source of truth** (Golden Record) for each entity, with classified metadata
- **Privacy-preserving encoding** that gives each partner a unique, irreversible key for the same entity
- **Controlled translation** (transcoding) between partner key spaces — with full policy enforcement and audit trails
- **Enrichment workflows** where partners can contribute and consume metadata without exposing raw entity data

## Core Use Cases

| # | Use Case | Description |
|---|----------|-------------|
| 1 | **Golden Record** | Maintain canonical entity records with classified metadata (INTERNAL / IDENTIFIABLE / ENRICHMENT) |
| 2 | **Resolution** | Find existing entities by identifiers or metadata using a multi-tier strategy (exact hash, Cortex Search AI) |
| 3 | **Encoding** | Generate partner-specific HMAC keys — deterministic, irreversible, unique per namespace |
| 4 | **Transcoding** | Translate between partner key spaces with policy checks, consent verification, and audit logging |
| 5 | **Enrichment Out** | Partners submit encoded IDs, receive back authorized metadata filtered by their clearance level |
| 6 | **Create Group** | Define structured entity groups with sub-categories (like audience segments), discoverable in a marketplace |
| 7 | **Contributions** | Partners define schemas and submit versioned metadata, discoverable in a marketplace with gated access |

## Architecture

```
                    React Frontend (Vite + TypeScript)
                              |
                        FastAPI Backend
                              |
                    Snowflake (ENTITY_VAULT_DB)
                    /    |    |    |    \    \
                CORE  RESOLUTION  ENCODING  ENRICHMENT  POLICY  AUDIT
```

- **100% Snowflake-native** — no external databases, no middleware
- **AI-powered resolution** using Snowflake Cortex Search for semantic matching
- **HMAC-SHA256 encoding** for irreversible partner-specific keys
- **Full audit trail** on every operation

## Quick Start

### Prerequisites

- Snowflake account with Cortex AI functions enabled
- Python 3.11+
- Node.js 20+
- Access to `SFSALESSHARED_SFC_SAMPLES_PROD3_SAMPLE_DATA` (TPC-DS sample data)

### 1. Set Up Snowflake

Run the SQL scripts in order:

```bash
# In a Snowflake worksheet or via SnowSQL:
sql/01_setup_database.sql    # Creates database, schemas, tables
sql/02_stored_procedures.sql # Creates all stored procedures and UDFs
sql/03_seed_tpcds.sql        # Seeds 200K+ product entities from TPC-DS
sql/04_seed_demo_data.sql    # Creates demo namespaces, encodings, contributions
```

### 2. Set Up Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your Snowflake credentials
uvicorn app.main:app --reload
```

### 3. Set Up Frontend

```bash
cd frontend
npm install
npm run dev
```

Open http://localhost:5173 in your browser.

## Project Structure

```
entity_vault_for_github/
├── sql/
│   ├── 01_setup_database.sql       # DDL: database, schemas, tables, views
│   ├── 02_stored_procedures.sql    # All stored procedures and UDFs
│   ├── 03_seed_tpcds.sql           # Seed from TPC-DS sample data
│   └── 04_seed_demo_data.sql       # Demo namespaces, encodings, contributions
├── backend/
│   ├── .env.example                # Configuration template
│   ├── requirements.txt            # Python dependencies
│   └── app/
│       ├── main.py                 # FastAPI application
│       ├── config.py               # Environment configuration
│       ├── snowflake_client.py     # Snowflake connection + SP caller
│       ├── models/                 # Pydantic request models
│       └── routers/                # API route handlers
│           ├── resolve.py          # POST /api/resolve
│           ├── encode.py           # POST /api/encode
│           ├── transcode.py        # POST /api/transcode
│           ├── enrich.py           # POST /api/enrich-out, /api/enrich-in (groups)
│           ├── contributions.py    # POST /api/contributions/*
│           ├── entities.py         # GET /api/entities
│           ├── namespaces.py       # GET/POST /api/namespaces
│           ├── audit.py            # GET /api/audit
│           └── demo.py             # GET /api/demo/* (random test data)
├── frontend/
│   ├── src/
│   │   ├── App.tsx                 # Main app with routing
│   │   ├── App.css                 # Global styles (dark theme)
│   │   ├── api/client.ts           # API client
│   │   ├── components/             # Reusable components
│   │   └── pages/                  # Page components (one per use case)
│   └── ...                         # Vite config, TypeScript config
├── docs/
│   └── index.html                  # Full project documentation
├── .gitignore
└── README.md
```

## Configuration

The backend supports three authentication methods:

| Method | `SNOWFLAKE_AUTH_METHOD` | Additional Config |
|--------|------------------------|-------------------|
| Password | `password` | Set `SNOWFLAKE_PASSWORD` |
| PAT Token File | `token_file` | Set `SNOWFLAKE_TOKEN_FILE` to file path |
| Browser SSO | `externalbrowser` | Requires SAML IdP configured |

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/resolve` | Resolve an entity by identifiers or metadata |
| POST | `/api/encode` | Generate a partner-specific encoded ID |
| POST | `/api/transcode` | Translate encoded ID between namespaces |
| POST | `/api/enrich-out` | Batch retrieve authorized metadata |
| POST | `/api/enrich-in` | Create entity groups with members |
| POST | `/api/contributions/schemas` | Define a contribution schema |
| POST | `/api/contributions/submit` | Submit batch contributions |
| GET | `/api/contributions/schemas` | Browse contribution marketplace |
| GET | `/api/entities` | Browse entities (paginated) |
| GET | `/api/entities/{id}` | Get entity detail |
| GET | `/api/namespaces` | List namespaces |
| GET | `/api/groups` | List discoverable groups |
| GET | `/api/audit` | Query audit log |

## Documentation

Open `docs/index.html` in a browser for comprehensive documentation including:
- Industry context (LiveRamp, Datavant comparison)
- Architecture deep dive
- Use case walkthroughs
- Future directions (ontology layer, Postgres backend)

## License

This project is provided for demonstration and educational purposes.
