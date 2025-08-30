#!/bin/bash

# Neo4j Memory Forensics Monitor
# Prevents catastrophic memory failures by tracking JVM heap, page cache, and transactions
# Based on lessons from FalkorDB's 7,762x memory explosion incident

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
CONTAINER_NAME="${NEO4J_CONTAINER:-neo4j}"
WARNING_HEAP_PERCENT=70
CRITICAL_HEAP_PERCENT=85
WARNING_GC_OVERHEAD=50
CRITICAL_GC_OVERHEAD=98
WARNING_PAGE_CACHE_HIT=98
CRITICAL_PAGE_CACHE_HIT=95

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}       Neo4j Memory Forensics Monitor          ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Check if Neo4j container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo -e "${RED}Error: Neo4j container '$CONTAINER_NAME' is not running${NC}"
    echo "Run 'docker compose up -d' to start it"
    exit 1
fi

# Function to format bytes to human readable
format_bytes() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes}B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(($bytes / 1024))KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(($bytes / 1048576))MB"
    else
        echo "$(($bytes / 1073741824))GB"
    fi
}

# Function to check Neo4j health
check_health() {
    echo -e "${YELLOW}🏥 Health Status:${NC}"
    
    # Check if Neo4j is responding
    if docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p password "RETURN 1" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Neo4j is responding${NC}"
    else
        echo -e "  ${RED}✗ Neo4j is not responding${NC}"
        echo -e "  ${YELLOW}⚠ Check credentials or connection${NC}"
    fi
    
    # Check container health status
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")
    case $HEALTH_STATUS in
        healthy)
            echo -e "  ${GREEN}✓ Container health: $HEALTH_STATUS${NC}"
            ;;
        unhealthy)
            echo -e "  ${RED}✗ Container health: $HEALTH_STATUS${NC}"
            ;;
        *)
            echo -e "  ${YELLOW}⚠ Container health: $HEALTH_STATUS${NC}"
            ;;
    esac
    echo ""
}

# Function to monitor JVM heap memory
monitor_heap() {
    echo -e "${YELLOW}🧠 JVM Heap Memory:${NC}"
    
    # Get JMX metrics via docker exec
    JVM_METRICS=$(docker exec "$CONTAINER_NAME" bash -c '
        echo "CALL dbms.queryJmx(\"java.lang:type=Memory\") YIELD attributes
        RETURN attributes.HeapMemoryUsage.used as used,
               attributes.HeapMemoryUsage.max as max,
               attributes.HeapMemoryUsage.committed as committed" | 
        cypher-shell -u neo4j -p password --format plain 2>/dev/null || echo "ERROR"
    ')
    
    if [[ "$JVM_METRICS" == "ERROR" ]]; then
        # Fallback to container stats
        CONTAINER_STATS=$(docker stats --no-stream --format "json" "$CONTAINER_NAME")
        MEM_USAGE=$(echo "$CONTAINER_STATS" | jq -r '.MemUsage' | cut -d'/' -f1 | sed 's/[^0-9.]//g')
        MEM_LIMIT=$(echo "$CONTAINER_STATS" | jq -r '.MemLimit' | sed 's/[^0-9.]//g')
        
        echo "  Current Usage: ${MEM_USAGE}GB"
        echo "  Memory Limit: ${MEM_LIMIT}GB"
        
        # Calculate percentage
        if [ -n "$MEM_LIMIT" ] && [ "$MEM_LIMIT" != "0" ]; then
            PERCENT=$(echo "scale=2; $MEM_USAGE / $MEM_LIMIT * 100" | bc)
            
            if (( $(echo "$PERCENT > $CRITICAL_HEAP_PERCENT" | bc -l) )); then
                echo -e "  ${RED}⚠ CRITICAL: Memory usage at ${PERCENT}%${NC}"
                echo -e "  ${RED}Action: Immediate attention required!${NC}"
            elif (( $(echo "$PERCENT > $WARNING_HEAP_PERCENT" | bc -l) )); then
                echo -e "  ${YELLOW}⚠ WARNING: Memory usage at ${PERCENT}%${NC}"
            else
                echo -e "  ${GREEN}✓ Memory usage at ${PERCENT}%${NC}"
            fi
        fi
    else
        # Parse JMX metrics if available
        echo "$JVM_METRICS" | tail -n +2 | while IFS='|' read -r used max committed; do
            echo "  Heap Used: $(format_bytes $used)"
            echo "  Heap Max: $(format_bytes $max)"
            echo "  Heap Committed: $(format_bytes $committed)"
            
            if [ "$max" -gt 0 ]; then
                PERCENT=$((used * 100 / max))
                if [ $PERCENT -gt $CRITICAL_HEAP_PERCENT ]; then
                    echo -e "  ${RED}⚠ CRITICAL: Heap usage at ${PERCENT}%${NC}"
                elif [ $PERCENT -gt $WARNING_HEAP_PERCENT ]; then
                    echo -e "  ${YELLOW}⚠ WARNING: Heap usage at ${PERCENT}%${NC}"
                else
                    echo -e "  ${GREEN}✓ Heap usage at ${PERCENT}%${NC}"
                fi
            fi
        done
    fi
    echo ""
}

# Function to check GC overhead
check_gc_overhead() {
    echo -e "${YELLOW}🗑️  Garbage Collection:${NC}"
    
    # Check for recent GC logs
    GC_LOG="/logs/gc.log"
    if docker exec "$CONTAINER_NAME" test -f "$GC_LOG" 2>/dev/null; then
        # Get last 100 lines of GC log and analyze
        RECENT_GC=$(docker exec "$CONTAINER_NAME" tail -100 "$GC_LOG" 2>/dev/null || echo "")
        
        if [ -n "$RECENT_GC" ]; then
            # Count pause events
            PAUSE_COUNT=$(echo "$RECENT_GC" | grep -c "Pause" || echo "0")
            echo "  Recent GC pauses: $PAUSE_COUNT"
            
            # Check for long pauses
            LONG_PAUSES=$(echo "$RECENT_GC" | grep -E "Pause.*[0-9]{4,}ms" || echo "")
            if [ -n "$LONG_PAUSES" ]; then
                echo -e "  ${YELLOW}⚠ Long GC pauses detected (>1000ms)${NC}"
            fi
            
            # Check for GC overhead limit
            if echo "$RECENT_GC" | grep -q "overhead limit"; then
                echo -e "  ${RED}⚠ CRITICAL: GC overhead limit exceeded!${NC}"
                echo -e "  ${RED}Action: Restart required or increase heap${NC}"
            fi
        fi
    else
        echo "  GC logs not available (enable with -Xlog:gc*)"
    fi
    echo ""
}

# Function to monitor page cache
monitor_page_cache() {
    echo -e "${YELLOW}📄 Page Cache Statistics:${NC}"
    
    # Query page cache metrics
    CACHE_METRICS=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p password \
        "CALL dbms.queryJmx('org.neo4j:instance=kernel#0,name=Page cache') 
         YIELD attributes 
         RETURN attributes" --format plain 2>/dev/null || echo "ERROR")
    
    if [[ "$CACHE_METRICS" != "ERROR" ]] && [[ -n "$CACHE_METRICS" ]]; then
        # Parse cache metrics
        echo "$CACHE_METRICS" | grep -E "Hit|Fault|Eviction" || echo "  No cache metrics available"
    else
        echo "  Page cache metrics not available"
        echo "  Tip: Check if JMX is enabled in neo4j.conf"
    fi
    echo ""
}

# Function to monitor transaction memory
monitor_transactions() {
    echo -e "${YELLOW}💰 Transaction Memory:${NC}"
    
    # Get transaction information
    TX_INFO=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p password \
        "SHOW TRANSACTIONS" --format plain 2>/dev/null || echo "ERROR")
    
    if [[ "$TX_INFO" != "ERROR" ]]; then
        TX_COUNT=$(echo "$TX_INFO" | grep -c "neo4j" || echo "0")
        echo "  Active transactions: $TX_COUNT"
        
        if [ "$TX_COUNT" -gt 0 ]; then
            # Show transaction details
            echo "$TX_INFO" | head -5 | while read line; do
                echo "    $line"
            done
            
            if [ "$TX_COUNT" -gt 5 ]; then
                echo "    ... and $((TX_COUNT - 5)) more"
            fi
        fi
    else
        echo "  Transaction monitoring requires Neo4j 4.1+"
    fi
    echo ""
}

# Function to check for memory anomalies
check_anomalies() {
    echo -e "${YELLOW}🔍 Memory Anomaly Detection:${NC}"
    
    # Check container restart count
    RESTART_COUNT=$(docker inspect "$CONTAINER_NAME" --format='{{.RestartCount}}' 2>/dev/null || echo "0")
    if [ "$RESTART_COUNT" -gt 0 ]; then
        echo -e "  ${YELLOW}⚠ Container restarted $RESTART_COUNT times${NC}"
        echo "  Check logs for OOM kills: docker logs $CONTAINER_NAME | grep -i 'out of memory'"
    fi
    
    # Check for heap dumps
    if docker exec "$CONTAINER_NAME" ls /data/dumps/*.hprof 2>/dev/null; then
        echo -e "  ${RED}⚠ Heap dumps detected in /data/dumps/${NC}"
        echo "  Analyze with: docker cp $CONTAINER_NAME:/data/dumps/ ./heap_dumps/"
    fi
    
    # Check for OOM killer activity
    if dmesg | tail -100 | grep -q "oom-kill.*$CONTAINER_NAME"; then
        echo -e "  ${RED}⚠ OOM killer activity detected for this container${NC}"
    fi
    
    # Check for memory configuration issues
    CONFIG_ISSUES=""
    
    # Get configured heap size
    HEAP_CONFIG=$(docker exec "$CONTAINER_NAME" grep -E "^dbms.memory.heap" /var/lib/neo4j/conf/neo4j.conf 2>/dev/null || echo "")
    if [ -z "$HEAP_CONFIG" ]; then
        CONFIG_ISSUES="${CONFIG_ISSUES}\n  ${YELLOW}⚠ No explicit heap configuration (using defaults)${NC}"
    fi
    
    # Check for transaction limits
    TX_LIMIT=$(docker exec "$CONTAINER_NAME" grep -E "^dbms.memory.transaction" /var/lib/neo4j/conf/neo4j.conf 2>/dev/null || echo "")
    if [ -z "$TX_LIMIT" ]; then
        CONFIG_ISSUES="${CONFIG_ISSUES}\n  ${YELLOW}⚠ No transaction memory limits set${NC}"
    fi
    
    if [ -n "$CONFIG_ISSUES" ]; then
        echo -e "$CONFIG_ISSUES"
    else
        echo -e "  ${GREEN}✓ No anomalies detected${NC}"
    fi
    echo ""
}

# Function to provide recommendations
provide_recommendations() {
    echo -e "${MAGENTA}📊 Recommendations:${NC}"
    
    # Get container memory limit
    MEM_LIMIT_BYTES=$(docker inspect "$CONTAINER_NAME" --format='{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
    
    if [ "$MEM_LIMIT_BYTES" = "0" ]; then
        echo -e "  ${YELLOW}• Set container memory limit to prevent host OOM${NC}"
        echo "    Add to docker-compose.yml: mem_limit: 8g"
    fi
    
    # Check if heap dumps are configured
    if ! docker exec "$CONTAINER_NAME" printenv | grep -q "HeapDumpOnOutOfMemoryError"; then
        echo -e "  ${YELLOW}• Enable heap dumps for forensics${NC}"
        echo "    Add JVM option: -XX:+HeapDumpOnOutOfMemoryError"
    fi
    
    # Suggest monitoring integration
    echo -e "  ${BLUE}• Integrate with Grafana for continuous monitoring${NC}"
    echo "    See: ../grafana-orbstack/docker-compose.grafana.yml"
    
    echo ""
}

# Function to generate summary
generate_summary() {
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Monitor complete at $(date)${NC}"
    
    # Quick status indicators
    echo -e "\n${YELLOW}Quick Status:${NC}"
    echo -n "  Health: " && check_health | grep -q "responding" && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
    echo -n "  Memory: " && monitor_heap | grep -q "CRITICAL" && echo -e "${RED}✗${NC}" || echo -e "${GREEN}✓${NC}"
    echo -n "  GC: " && check_gc_overhead | grep -q "CRITICAL" && echo -e "${RED}✗${NC}" || echo -e "${GREEN}✓${NC}"
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════${NC}"
}

# Main monitoring flow
check_health
monitor_heap
check_gc_overhead
monitor_page_cache
monitor_transactions
check_anomalies
provide_recommendations
generate_summary

# Exit with appropriate code
if monitor_heap | grep -q "CRITICAL" || check_gc_overhead | grep -q "CRITICAL"; then
    exit 2  # Critical condition
elif monitor_heap | grep -q "WARNING" || check_anomalies | grep -q "WARNING"; then
    exit 1  # Warning condition
else
    exit 0  # All good
fi