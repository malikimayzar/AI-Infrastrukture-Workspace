"""
Deep Health Check Utilities for AI Infrastructure Workspace

Provides comprehensive health checking for dependencies:
- PostgreSQL database connectivity
- Qdrant vector database connectivity
- Ollama LLM service availability
- Model loading status

Usage:
    from health_check_utils import HealthChecker, check_postgres, check_qdrant, check_ollama

    checker = HealthChecker()
    results = checker.check_all()
"""

import asyncio
import os
import time
from dataclasses import dataclass
from enum import Enum
from typing import Dict, List, Optional
import aiohttp
import asyncpg
import requests


class HealthStatus(Enum):
    """Health check status"""

    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"
    UNKNOWN = "unknown"


@dataclass
class HealthCheckResult:
    """Result of a health check"""

    component: str
    status: HealthStatus
    message: str
    latency_ms: float
    details: Optional[Dict] = None


class HealthChecker:
    """Comprehensive health checker for AI infrastructure services"""

    def __init__(self):
        self.postgres_host = os.getenv("DB_HOST", "localhost")
        self.postgres_port = int(os.getenv("DB_PORT", "5432"))
        self.postgres_user = os.getenv("DB_USER", "arxiv")
        self.postgres_password = os.getenv("DB_PASSWORD", "arxiv_secret")
        self.postgres_db = os.getenv("DB_NAME", "arxiv_db")

        self.qdrant_url = os.getenv("QDRANT_URL", "http://localhost:6333")
        self.ollama_host = os.getenv("OLLAMA_HOST", "http://localhost:11434")

    async def check_postgres(self) -> HealthCheckResult:
        """Check PostgreSQL database connectivity"""
        start_time = time.time()
        try:
            conn = await asyncpg.connect(
                host=self.postgres_host,
                port=self.postgres_port,
                user=self.postgres_user,
                password=self.postgres_password,
                database=self.postgres_db,
                timeout=5.0,
            )

            # Test simple query
            version = await conn.fetchval("SELECT version()")
            await conn.close()

            latency_ms = (time.time() - start_time) * 1000
            return HealthCheckResult(
                component="postgres",
                status=HealthStatus.HEALTHY,
                message=f"PostgreSQL connected successfully",
                latency_ms=latency_ms,
                details={
                    "version": version[:50] + "..." if len(version) > 50 else version
                },
            )
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            return HealthCheckResult(
                component="postgres",
                status=HealthStatus.UNHEALTHY,
                message=f"PostgreSQL connection failed: {str(e)}",
                latency_ms=latency_ms,
                details={"error": str(e)},
            )

    async def check_qdrant(self) -> HealthCheckResult:
        """Check Qdrant vector database connectivity"""
        start_time = time.time()
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f"{self.qdrant_url}/", timeout=aiohttp.ClientTimeout(total=5.0)
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        latency_ms = (time.time() - start_time) * 1000
                        return HealthCheckResult(
                            component="qdrant",
                            status=HealthStatus.HEALTHY,
                            message="Qdrant connected successfully",
                            latency_ms=latency_ms,
                            details={"version": data.get("title", "unknown")},
                        )
                    else:
                        latency_ms = (time.time() - start_time) * 1000
                        return HealthCheckResult(
                            component="qdrant",
                            status=HealthStatus.UNHEALTHY,
                            message=f"Qdrant returned status {response.status}",
                            latency_ms=latency_ms,
                        )
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            return HealthCheckResult(
                component="qdrant",
                status=HealthStatus.UNHEALTHY,
                message=f"Qdrant connection failed: {str(e)}",
                latency_ms=latency_ms,
                details={"error": str(e)},
            )

    async def check_ollama(self) -> HealthCheckResult:
        """Check Ollama LLM service availability"""
        start_time = time.time()
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f"{self.ollama_host}/api/tags",
                    timeout=aiohttp.ClientTimeout(total=5.0),
                ) as response:
                    if response.status == 200:
                        data = await response.json()
                        models = data.get("models", [])
                        latency_ms = (time.time() - start_time) * 1000
                        return HealthCheckResult(
                            component="ollama",
                            status=HealthStatus.HEALTHY,
                            message=f"Ollama connected, {len(models)} models available",
                            latency_ms=latency_ms,
                            details={
                                "model_count": len(models),
                                "models": [m.get("name") for m in models[:5]],
                            },
                        )
                    else:
                        latency_ms = (time.time() - start_time) * 1000
                        return HealthCheckResult(
                            component="ollama",
                            status=HealthStatus.UNHEALTHY,
                            message=f"Ollama returned status {response.status}",
                            latency_ms=latency_ms,
                        )
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            return HealthCheckResult(
                component="ollama",
                status=HealthStatus.UNHEALTHY,
                message=f"Ollama connection failed: {str(e)}",
                latency_ms=latency_ms,
                details={"error": str(e)},
            )

    async def check_embedding_model(self) -> HealthCheckResult:
        """Check if embedding model is loaded (for services using sentence-transformers)"""
        start_time = time.time()
        try:
            # This is a placeholder - actual implementation depends on the service
            # Services should override this method with their specific check
            latency_ms = (time.time() - start_time) * 1000
            return HealthCheckResult(
                component="embedding_model",
                status=HealthStatus.UNKNOWN,
                message="Embedding model check not implemented",
                latency_ms=latency_ms,
            )
        except Exception as e:
            latency_ms = (time.time() - start_time) * 1000
            return HealthCheckResult(
                component="embedding_model",
                status=HealthStatus.UNHEALTHY,
                message=f"Embedding model check failed: {str(e)}",
                latency_ms=latency_ms,
            )

    async def check_all(self) -> Dict[str, HealthCheckResult]:
        """Run all health checks"""
        results = {}

        # Run all checks concurrently
        tasks = [
            self.check_postgres(),
            self.check_qdrant(),
            self.check_ollama(),
            self.check_embedding_model(),
        ]

        check_results = await asyncio.gather(*tasks, return_exceptions=True)

        for i, result in enumerate(check_results):
            if isinstance(result, Exception):
                component = ["postgres", "qdrant", "ollama", "embedding_model"][i]
                results[component] = HealthCheckResult(
                    component=component,
                    status=HealthStatus.UNHEALTHY,
                    message=f"Health check raised exception: {str(result)}",
                    latency_ms=0,
                )
            else:
                results[result.component] = result

        return results

    def get_overall_status(self, results: Dict[str, HealthCheckResult]) -> HealthStatus:
        """Determine overall health status from individual results"""
        if not results:
            return HealthStatus.UNKNOWN

        statuses = [r.status for r in results.values()]

        if all(s == HealthStatus.HEALTHY for s in statuses):
            return HealthStatus.HEALTHY
        elif any(s == HealthStatus.UNHEALTHY for s in statuses):
            return HealthStatus.UNHEALTHY
        else:
            return HealthStatus.DEGRADED


# Synchronous wrapper functions for non-async contexts
def check_postgres_sync() -> HealthCheckResult:
    """Synchronous wrapper for PostgreSQL check"""

    async def _check():
        checker = HealthChecker()
        return await checker.check_postgres()

    return asyncio.run(_check())


def check_qdrant_sync() -> HealthCheckResult:
    """Synchronous wrapper for Qdrant check"""

    async def _check():
        checker = HealthChecker()
        return await checker.check_qdrant()

    return asyncio.run(_check())


def check_ollama_sync() -> HealthCheckResult:
    """Synchronous wrapper for Ollama check"""

    async def _check():
        checker = HealthChecker()
        return await checker.check_ollama()

    return asyncio.run(_check())


def check_all_sync() -> Dict[str, HealthCheckResult]:
    """Synchronous wrapper for all checks"""

    async def _check():
        checker = HealthChecker()
        return await checker.check_all()

    return asyncio.run(_check())
