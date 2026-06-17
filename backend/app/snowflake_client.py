import json
import snowflake.connector
from contextlib import contextmanager
from app.config import (
    SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_AUTH_METHOD,
    SNOWFLAKE_PASSWORD, SNOWFLAKE_TOKEN_FILE,
    SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DATABASE, SNOWFLAKE_ROLE,
)


def get_connection():
    params = {
        "account": SNOWFLAKE_ACCOUNT,
        "user": SNOWFLAKE_USER,
        "warehouse": SNOWFLAKE_WAREHOUSE,
        "database": SNOWFLAKE_DATABASE,
        "role": SNOWFLAKE_ROLE,
    }

    if SNOWFLAKE_AUTH_METHOD == "token_file":
        with open(SNOWFLAKE_TOKEN_FILE, "r") as f:
            params["password"] = f.read().strip()
    elif SNOWFLAKE_AUTH_METHOD == "externalbrowser":
        params["authenticator"] = "externalbrowser"
    else:
        params["password"] = SNOWFLAKE_PASSWORD

    return snowflake.connector.connect(**params)


@contextmanager
def get_cursor():
    conn = get_connection()
    try:
        cur = conn.cursor()
        yield cur
    finally:
        cur.close()
        conn.close()


def call_procedure(procedure_name: str, *args) -> dict:
    with get_cursor() as cur:
        placeholder_parts = []
        processed_args = []
        for arg in args:
            if arg is None:
                placeholder_parts.append("%s")
                processed_args.append(None)
            elif isinstance(arg, (dict, list)):
                placeholder_parts.append("PARSE_JSON(%s)")
                processed_args.append(json.dumps(arg))
            else:
                placeholder_parts.append("%s")
                processed_args.append(arg)
        placeholders = ", ".join(placeholder_parts)
        sql = f"CALL {procedure_name}({placeholders})"
        cur.execute(sql, processed_args)
        row = cur.fetchone()
        if row and row[0]:
            result = row[0]
            if isinstance(result, str):
                return json.loads(result)
            return result
        return {}


def execute_query(sql: str, params: tuple = None) -> list[dict]:
    with get_cursor() as cur:
        cur.execute(sql, params or ())
        columns = [desc[0].lower() for desc in cur.description]
        rows = cur.fetchall()
        return [dict(zip(columns, row)) for row in rows]
