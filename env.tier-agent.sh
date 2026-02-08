# PMOVES.AI Tier Environment: Agent
# For Agent and Orchestrator services (Agent Zero, Archon, etc.)
# Source after env.shared: source env.shared && source env.tier-agent.sh

# ============================================================================
# Agent Tier Configuration
# ============================================================================

export TIER=agent

# Agent limits
export MAX_CONCURRENT_AGENTS=${MAX_CONCURRENT_AGENTS:-50}
export MAX_TASKS_PER_AGENT=${MAX_TASKS_PER_AGENT:-10}
export AGENT_TIMEOUT_MS=${AGENT_TIMEOUT_MS:-300000}  # 5 minutes
export AGENT_IDLE_TIMEOUT_MS=${AGENT_IDLE_TIMEOUT_MS:-60000}  # 1 minute

# Task queue configuration
export TASK_QUEUE_SIZE=${TASK_QUEUE_SIZE:-1000}
export TASK_RETRY_MAX=${TASK_RETRY_MAX:-3}
export TASK_RETRY_DELAY_MS=${TASK_RETRY_DELAY_MS:-1000}

# Tool execution
export TOOL_TIMEOUT_MS=${TOOL_TIMEOUT_MS:-60000}  # 1 minute
export MAX_TOOL_OUTPUT_SIZE=${MAX_TOOL_OUTPUT_SIZE:-1048576}  # 1MB

# MCP (Model Context Protocol) configuration
export MCP_ENABLED=${MCP_ENABLED:-true}
export MCP_TIMEOUT_MS=${MCP_TIMEOUT_MS:-30000}
export MCP_MAX_MESSAGE_SIZE=${MCP_MAX_MESSAGE_SIZE:-10485760}  # 10MB

# Agent state persistence
export STATE_PERSISTENCE_ENABLED=${STATE_PERSISTENCE_ENABLED:-true}
export STATE_BACKEND=${STATE_BACKEND:-supabase}  # supabase | memory | file

# LLM configuration for agents
export DEFAULT_MODEL=${DEFAULT_MODEL:-claude-sonnet-4-5}
export DEFAULT_TEMPERATURE=${DEFAULT_TEMPERATURE:-0.7}
export DEFAULT_MAX_TOKENS=${DEFAULT_MAX_TOKENS:-4096}

# Prompt management
export PROMPT_CACHE_ENABLED=${PROMPT_CACHE_ENABLED:-true}
export PROMPT_CACHE_SIZE=${PROMPT_CACHE_SIZE:-1000}
export PROMPT_CACHE_TTL=${PROMPT_CACHE_TTL:-3600}  # 1 hour

# Archon-specific (if using Archon)
export ARCHON_PROMPT_BACKEND=${ARCHON_PROMPT_BACKEND:-supabase}
export ARCHON_FORM_SCHEMA_PATH=${ARCHON_FORM_SCHEMA_PATH:-/forms}
