"""
FastAPI Health Check Endpoints

Provides /health and /health/deep endpoints for AI infrastructure services.

Integration Example:
    from health_check_api import add_health_routes
    from fastapi import FastAPI

    app = FastAPI()
    add_health_routes(app, service_name="rag-api")
"""

import sys
import os
from fastapi import FastAPI
from fastapi.responses import JSONResponse

# Add scripts directory to path before importing sibling modules so the
# documented `from health_check_api import add_health_routes` works from any cwd.
_SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from health_check_utils import HealthChecker, HealthStatus  # noqa: E402


def add_health_routes(app: FastAPI, service_name: str = "unknown"):
    """
    Add health check endpoints to FastAPI application

    Args:
        app: FastAPI application instance
        service_name: Name of the service (for logging)
    """

    @app.get("/health")
    async def health():
        """
        Basic health check (liveness probe)
        Returns 200 if service is running, 503 if not
        """
        return {"status": "healthy", "service": service_name}

    @app.get("/health/deep")
    async def health_deep():
        """
        Deep health check (readiness probe)
        Checks all dependencies: PostgreSQL, Qdrant, Ollama, embedding model
        Returns detailed status of each component
        """
        checker = HealthChecker()
        results = await checker.check_all()
        overall_status = checker.get_overall_status(results)

        # Format results for JSON response
        formatted_results = {}
        for component, result in results.items():
            formatted_results[component] = {
                "status": result.status.value,
                "message": result.message,
                "latency_ms": round(result.latency_ms, 2),
                "details": result.details,
            }

        response_data = {
            "status": overall_status.value,
            "service": service_name,
            "checks": formatted_results,
        }

        # Return appropriate HTTP status code
        if overall_status == HealthStatus.HEALTHY:
            return JSONResponse(content=response_data, status_code=200)
        elif overall_status == HealthStatus.DEGRADED:
            return JSONResponse(content=response_data, status_code=200)  # Still serving
        else:
            return JSONResponse(content=response_data, status_code=503)


# Standalone test server (for development)
if __name__ == "__main__":
    import uvicorn

    app = FastAPI()
    add_health_routes(app, service_name="health-check-test")

    print("Starting health check test server on http://localhost:8888")
    print("Endpoints:")
    print("  - http://localhost:8888/health")
    print("  - http://localhost:8888/health/deep")

    uvicorn.run(app, host="0.0.0.0", port=8888)
