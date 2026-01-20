# PMOVES.AI Tier Environment: UI
# For UI and Dashboard services
# Source after env.shared: source env.shared && source env.tier-ui.sh

# ============================================================================
# UI Tier Configuration
# ============================================================================

export TIER=ui

# Build configuration
export NODE_ENV=${NODE_ENV:-production}
export NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL:-http://localhost:8080}

# Feature flags
export FEATURE_DARK_MODE=${FEATURE_DARK_MODE:-true}
export FEATURE_METRICS=${FEATURE_METRICS:-true}

# API endpoints (for client-side calls)
export NEXT_PUBLIC_AGENT_ZERO_URL=${NEXT_PUBLIC_AGENT_ZERO_URL:-http://agent-zero:8080}
export NEXT_PUBLIC_HIRAG_URL=${NEXT_PUBLIC_HIRAG_URL:-http://hi-rag-gateway-v2:8086}
