"""
Structured JSON Logging Utilities for AI Infrastructure Workspace

Provides a unified logging interface that outputs JSON-structured logs
with consistent fields: timestamp, level, service, request_id, duration_ms, etc.

Usage:
    from logging_utils import get_logger

    logger = get_logger("rag-api")
    logger.info("Processing query", extra={"query": "test", "top_k": 5})
"""

import json
import logging
import sys
import time
import uuid
from datetime import datetime
from typing import Any, Dict, Optional
from contextlib import contextmanager


class JSONFormatter(logging.Formatter):
    """Custom formatter that outputs logs as JSON"""

    def format(self, record: logging.LogRecord) -> str:
        log_data = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "service": getattr(record, "service", "unknown"),
            "message": record.getMessage(),
            "logger": record.name,
        }

        # Add optional fields if present
        if hasattr(record, "request_id"):
            log_data["request_id"] = record.request_id
        if hasattr(record, "duration_ms"):
            log_data["duration_ms"] = record.duration_ms
        if hasattr(record, "backend"):
            log_data["backend"] = record.backend
        if hasattr(record, "error"):
            log_data["error"] = record.error

        # Add any extra fields from the log call
        if hasattr(record, "extra_fields"):
            log_data.update(record.extra_fields)

        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_data)


def get_logger(
    service_name: str, level: int = logging.INFO, output: str = "stdout"
) -> logging.Logger:
    """
    Get a configured logger for a service

    Args:
        service_name: Name of the service (e.g., "rag-api", "mcp-gateway")
        level: Logging level (default: INFO)
        output: Output destination ("stdout" or "stderr")

    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(service_name)
    logger.setLevel(level)

    # Avoid adding multiple handlers
    if not logger.handlers:
        handler = logging.StreamHandler(
            sys.stdout if output == "stdout" else sys.stderr
        )
        handler.setFormatter(JSONFormatter())
        logger.addHandler(handler)

    # Add service name to each log record
    class ServiceFilter(logging.Filter):
        def filter(self, record):
            record.service = service_name
            return True

    logger.addFilter(ServiceFilter())

    return logger


@contextmanager
def log_duration(logger: logging.Logger, operation: str, **extra_fields: Any):
    """
    Context manager to log operation duration

    Usage:
        with log_duration(logger, "query_processing", query_id="123"):
            # do work
    """
    start_time = time.time()
    request_id = extra_fields.get("request_id", str(uuid.uuid4()))

    logger.info(
        f"{operation} started",
        extra={"extra_fields": {**extra_fields, "request_id": request_id}},
    )

    try:
        yield request_id
        duration_ms = (time.time() - start_time) * 1000
        logger.info(
            f"{operation} completed",
            extra={
                "extra_fields": {
                    **extra_fields,
                    "request_id": request_id,
                    "duration_ms": duration_ms,
                }
            },
        )
    except Exception as e:
        duration_ms = (time.time() - start_time) * 1000
        logger.error(
            f"{operation} failed",
            extra={
                "extra_fields": {
                    **extra_fields,
                    "request_id": request_id,
                    "duration_ms": duration_ms,
                    "error": str(e),
                }
            },
            exc_info=True,
        )
        raise


def log_with_context(
    logger: logging.Logger,
    level: int,
    message: str,
    request_id: Optional[str] = None,
    **extra_fields: Any,
):
    """
    Log a message with structured context

    Args:
        logger: Logger instance
        level: Log level (logging.INFO, logging.ERROR, etc.)
        message: Log message
        request_id: Optional request ID for tracing
        **extra_fields: Additional structured fields
    """
    if request_id is None:
        request_id = str(uuid.uuid4())

    extra = {"extra_fields": {**extra_fields, "request_id": request_id}}
    logger.log(level, message, extra=extra)


# Convenience functions
def log_info(
    logger: logging.Logger,
    message: str,
    request_id: Optional[str] = None,
    **extra_fields: Any,
):
    """Log at INFO level with context"""
    log_with_context(logger, logging.INFO, message, request_id, **extra_fields)


def log_error(
    logger: logging.Logger,
    message: str,
    request_id: Optional[str] = None,
    **extra_fields: Any,
):
    """Log at ERROR level with context"""
    log_with_context(logger, logging.ERROR, message, request_id, **extra_fields)


def log_warning(
    logger: logging.Logger,
    message: str,
    request_id: Optional[str] = None,
    **extra_fields: Any,
):
    """Log at WARNING level with context"""
    log_with_context(logger, logging.WARNING, message, request_id, **extra_fields)


def log_debug(
    logger: logging.Logger,
    message: str,
    request_id: Optional[str] = None,
    **extra_fields: Any,
):
    """Log at DEBUG level with context"""
    log_with_context(logger, logging.DEBUG, message, request_id, **extra_fields)
