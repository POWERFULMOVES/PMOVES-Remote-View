"""
PMOVES.AI Common Types Module

Shared types for PMOVES.AI integration patterns.
"""
from enum import Enum


class ServiceTier(str, Enum):
    """PMOVES service tiers (6-tier architecture)."""
    DATA = "data"
    API = "api"
    LLM = "llm"
    WORKER = "worker"
    MEDIA = "media"
    AGENT = "agent"


class HealthStatus(str, Enum):
    """Health status constants for service health checks."""
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"
