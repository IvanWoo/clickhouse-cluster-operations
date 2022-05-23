#!/usr/bin/env python3
import argparse
from operator import itemgetter
import os
import shlex
import subprocess
import logging
from enum import Enum
from urllib.parse import urlparse

logger = logging.getLogger(__name__)
logging.getLogger().addHandler(logging.StreamHandler())

SCHEMA_MIGRATIONS_DDL = """
CREATE TABLE IF NOT EXISTS schema_migrations ON CLUSTER '{cluster}' 
(
    version String,
    ts DateTime DEFAULT now(),
    applied UInt8 DEFAULT 1
)
ENGINE = ReplicatedReplacingMergeTree('/clickhouse/{cluster}/tables/{database}/{table}', '{replica}', ts)
PRIMARY KEY version
ORDER BY version;
"""


def db_url():
    return os.environ["DATABASE_URL"]


def update_db_url(db):
    original_db_url = db_url()
    os.environ["DATABASE_URL"] = f"{original_db_url}/{db}"


def parse_db_url(url):
    parsed = urlparse(url)
    return {
        "hostname": parsed.hostname,
        "port": parsed.port,
        "username": parsed.username,
        "password": parsed.password,
    }


def run(cmd):
    return subprocess.run(shlex.split(cmd), capture_output=True)


def compile_cmd(db):
    parsed_db_url = parse_db_url(db_url())
    hostname, port, username, password = itemgetter(
        "hostname", "port", "username", "password"
    )(parsed_db_url)
    return f'clickhouse-client -h {hostname} --port {port} -u {username} --password {password} -d {db} --query="{SCHEMA_MIGRATIONS_DDL}"'


def create_metadata_table(db):
    cmd = compile_cmd(db)
    res = run(cmd)
    if res.stderr:
        logger.warning(res.stderr)
        return
    logger.info(res.stdout)
    return


def run_dbmate_operation(operation):
    res = run(f"dbmate {operation}")
    if res.stderr:
        logger.warning(res.stderr)
        return
    logger.info(res.stdout)
    return


class Database(Enum):
    TEST = "test"

    def __str__(self):
        return self.value


class DbMateOperation(Enum):
    STATUS = "status"
    UP = "up"
    DOWN = "down"
    MIGRATE = "migrate"
    ROLLBACK = "rollback"

    def __str__(self):
        return self.value


def main():
    parser = argparse.ArgumentParser(description="Clickhouse Migration Tool")
    parser.add_argument(
        "-db",
        "--database",
        required=True,
        type=Database,
        choices=list(Database),
        help="target database",
    )
    parser.add_argument(
        "operation",
        type=DbMateOperation,
        choices=list(DbMateOperation),
        help="dbmate operations",
    )

    args = parser.parse_args()

    update_db_url(args.database)
    create_metadata_table(args.database)
    run_dbmate_operation(args.operation)


if __name__ == "__main__":
    main()
