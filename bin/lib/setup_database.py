"""Select PostgreSQL targets and refuse databases not owned by this checkout."""
import os
from pathlib import Path
import socket
from urllib.parse import parse_qsl, unquote, urlsplit

from setup_preflight import SetupError, capture


def nonempty(name):
    value = os.environ.get(name)
    return value if value and value.strip() else None


def target(environment, default_database):
    url = (nonempty("VXPIPE_DB_URL") or nonempty("DATABASE_URL")) if environment == "dev" else nonempty("VXPIPE_TEST_DATABASE_URL")
    connection = {key: value for key, value in os.environ.items() if key.startswith("PG")}
    # Do not inherit a database/service target unrelated to the selected environment.
    for key in ("PGDATABASE", "PGSERVICE", "PGSERVICEFILE"):
        connection.pop(key, None)
    database = default_database
    if environment == "test":
        database = nonempty("VXPIPE_TEST_DATABASE") or database
    if url:
        try:
            parsed = urlsplit(url)
            database = unquote(parsed.path.removeprefix("/"))
            if parsed.scheme not in ("postgres", "postgresql") or not parsed.hostname or not database or "/" in database or parsed.fragment:
                raise ValueError()
            connection["PGHOST"] = parsed.hostname
            connection["PGPORT"] = str(parsed.port or 5432)
            if parsed.username is not None:
                connection["PGUSER"] = unquote(parsed.username)
            if parsed.password is not None:
                connection["PGPASSWORD"] = unquote(parsed.password)
            for key, value in parse_qsl(parsed.query):
                if key == "ssl":
                    if value not in ("true", "false"):
                        raise ValueError()
                    connection["PGSSLMODE"] = "require" if value == "true" else "disable"
                elif key == "socket_dir":
                    connection["PGHOST"] = value
                elif key != "pool_size":
                    raise ValueError()
        except ValueError:
            raise SetupError(f"invalid or unsupported {environment} database URL; use a PostgreSQL URL with one database name") from None
    else:
        port = nonempty("PGPORT") or "5432"
        local_socket = next((directory for directory in ("/var/run/postgresql", "/tmp")
                             if Path(directory, f".s.PGSQL.{port}").exists()), None)
        connection["PGHOST"] = nonempty("PGHOST") or local_socket or "localhost"
        connection["PGPORT"] = port
    connection["PGUSER"] = connection.get("PGUSER") or os.environ["USER"]
    connection.update(PGDATABASE="postgres", PGCONNECT_TIMEOUT="5")
    return {"environment": environment, "database": database, "connection": connection}


def target_key(selected):
    host = selected["connection"]["PGHOST"]
    if host.startswith("/") or host in ("localhost", "127.0.0.1", "::1"):
        host = "local"
    else:
        try:
            host = socket.gethostbyname(host)
        except OSError:
            pass
    return host, selected["connection"]["PGPORT"], selected["database"]


def psql(selected, query, variables=()):
    arguments = ["psql", "-X", "--no-password", "-At", "-v", "ON_ERROR_STOP=1"]
    for key, value in variables:
        arguments.extend(["-v", f"{key}={value}"])
    # stdin supports psql's quoted variables; secrets remain exclusively in env.
    environment = {key: value for key, value in os.environ.items() if not key.startswith("PG")}
    return capture(arguments, environment=environment | selected["connection"], input_text=query)


def preflight_connections():
    selected = [target(environment, "postgres") for environment in ("dev", "test")]
    for connection in selected:
        result = psql(connection, "SELECT rolcanlogin AND (rolcreatedb OR rolsuper) FROM pg_roles WHERE rolname = current_user;")
        if result is None:
            raise SetupError(f"cannot connect to {connection['environment']} PostgreSQL; start the server and check the selected connection settings")
        if result != "t":
            raise SetupError("the PostgreSQL role needs LOGIN and CREATEDB; ask its administrator to grant them")


def prepare_databases(metadata):
    selected = [target(environment, metadata["databases"][environment]) for environment in ("dev", "test")]
    if target_key(selected[0]) == target_key(selected[1]):
        raise SetupError("development and test select the same database; supply separate targets before setup")
    # Check both before creating or migrating either target.
    for connection in selected:
        marker = f"vxpipe:{metadata['id']}:{connection['environment']}"
        result = psql(connection, "SELECT COALESCE((SELECT COALESCE(shobj_description(oid, 'pg_database') = :'owner', false) FROM pg_database WHERE datname = :'database'), true);",
                      (("owner", marker), ("database", connection["database"])))
        if result != "t":
            raise SetupError(f"{connection['environment']} database is unowned, belongs to another checkout, or cannot be inspected; choose a fresh target")
    for connection in selected:
        marker = f"vxpipe:{metadata['id']}:{connection['environment']}"
        # The advisory lock covers only creation/ownership publication, never a test
        # run. Recheck under the lock so competing setup cannot adopt the winner's DB.
        query = r"""
SET statement_timeout = '30s';
SELECT pg_advisory_lock(hashtextextended('vxpipe.setup.' || :'database', 0));
SELECT EXISTS (SELECT FROM pg_database WHERE datname = :'database') AS present \gset
\if :present
SELECT COALESCE((SELECT shobj_description(oid, 'pg_database') = :'owner' FROM pg_database WHERE datname = :'database'), false) AS owned \gset
\if :owned
\else
DO $vxpipe$ BEGIN RAISE EXCEPTION 'database is not owned by this checkout'; END $vxpipe$;
\endif
\else
SELECT format('CREATE DATABASE %I', :'database') \gexec
SELECT format('COMMENT ON DATABASE %I IS %L', :'database', :'owner') \gexec
\endif
"""
        if psql(connection, query, (("owner", marker), ("database", connection["database"]))) is None:
            raise SetupError(f"{connection['environment']} database creation/ownership check failed; existing data was preserved")
    return selected
