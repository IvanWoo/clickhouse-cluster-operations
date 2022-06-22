#!/usr/bin/env python3
import argparse
import os
import shlex
import subprocess
import logging
from enum import Enum
from operator import itemgetter
from urllib.parse import urlparse


class ClickhouseMigrationException(Exception):
    pass


class MetadataError(ClickhouseMigrationException):
    pass


class OperationError(ClickhouseMigrationException):
    pass


def get_logger(logger_name):
    FORMATTER = logging.Formatter(
        "%(asctime)s %(name)s %(funcName)s %(lineno)d %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S%z",
    )

    def get_sys_handler():
        syslog = logging.StreamHandler()
        syslog.setFormatter(FORMATTER)
        return syslog

    logger = logging.getLogger(logger_name)
    logger.addHandler(get_sys_handler())
    return logger


logger = get_logger(__file__)

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


class Database(Enum):
    TEST = "test"
    TEST_DEVELOPMENT = "test_development"
    TEST_TEST = "test_test"

    def __str__(self):
        return self.value


DATABASE_CONFIG = {
    Database.TEST: {
        "database_name": "test",
        "migrations_dir": "./databases/test/migrations",
        "schema_file": "./databases/test/schema.sql",
    },
    Database.TEST_DEVELOPMENT: {
        "database_name": "test_development",
        "migrations_dir": "./databases/test/migrations",
        "schema_file": "./databases/test/schema.sql",
    },
    Database.TEST_TEST: {
        "database_name": "test_test",
        "migrations_dir": "./databases/test/migrations",
        "schema_file": "./databases/test/schema.sql",
    },
}


def db_url():
    return os.environ["DATABASE_URL"]


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


def compile_clickhouse_query_cmd(db, query):
    parsed_db_url = parse_db_url(db_url())
    hostname, port, username, password = itemgetter(
        "hostname", "port", "username", "password"
    )(parsed_db_url)

    return f'clickhouse-client -h {hostname} --port {port} -u {username} --password {password} -d {db} --query="{query}"'


def compile_dbmate_operation_cmd(db, operation, parameters):
    database_name, migrations_dir, schema_file = itemgetter(
        "database_name", "migrations_dir", "schema_file"
    )(DATABASE_CONFIG[db])
    database_url = f"{db_url()}/{database_name}"

    return f"dbmate --url {database_url} --migrations-dir {migrations_dir} --schema-file {schema_file} {operation} {parameters}"


def create_metadata_table(db):
    cmd = compile_clickhouse_query_cmd(db, SCHEMA_MIGRATIONS_DDL)
    res = run(cmd)
    if res.stderr:
        logger.error(res.stderr)
        raise MetadataError
    logger.critical(res.stdout)
    return


def run_dbmate_operation(db, operation, parameters):
    cmd = compile_dbmate_operation_cmd(db, operation, parameters)
    res = run(cmd)
    if res.stderr:
        logger.error(res.stderr)
        raise OperationError
    logger.critical(res.stdout)
    return


class DbmateOperation(Enum):
    HELP = "help"
    NEW = "new"
    STATUS = "status"
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
        "-p",
        "--parameters",
        help="dbmate operation additional paramters",
    )
    parser.add_argument(
        "operation",
        type=DbmateOperation,
        choices=list(DbmateOperation),
        help="dbmate operation",
    )

    args = parser.parse_args()

    database = args.database
    operation = args.operation
    parameters = args.parameters

    create_metadata_table(database)
    run_dbmate_operation(database, operation, parameters)
    return


if __name__ == "__main__":
    main()
