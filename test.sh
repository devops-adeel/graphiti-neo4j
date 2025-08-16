#!/bin/bash

# Neo4j Graphiti Test Runner
# Run various test suites for Graphiti on Neo4j

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test directory
TEST_DIR="tests"

# Default test suite
SUITE=${1:-all}

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if Neo4j is running
check_neo4j() {
    print_color "$BLUE" "Checking Neo4j connection..."
    
    if docker ps | grep -q neo4j-graphiti; then
        print_color "$GREEN" "✓ Neo4j container is running"
    else
        print_color "$RED" "✗ Neo4j container is not running"
        print_color "$YELLOW" "Starting Neo4j..."
        docker-compose up -d
        sleep 10  # Wait for Neo4j to start
    fi
}

# Function to install dependencies
install_deps() {
    print_color "$BLUE" "Installing test dependencies..."
    pip install -r tests/requirements.txt
    print_color "$GREEN" "✓ Dependencies installed"
}

# Function to run tests
run_tests() {
    local suite=$1
    
    case $suite in
        quick)
            print_color "$BLUE" "Running quick smoke tests..."
            pytest $TEST_DIR/test_graphiti_search_performance.py::TestGraphitiSearchPerformance::test_search_nodes_warm_cache -v
            pytest $TEST_DIR/test_graphiti_episode_processing.py::TestGraphitiEpisodeProcessing::test_text_episode_processing -v
            ;;
            
        search)
            print_color "$BLUE" "Running search performance tests..."
            pytest $TEST_DIR/test_graphiti_search_performance.py -v
            ;;
            
        episode)
            print_color "$BLUE" "Running episode processing tests..."
            pytest $TEST_DIR/test_graphiti_episode_processing.py -v
            ;;
            
        concurrent)
            print_color "$BLUE" "Running concurrent agent tests..."
            pytest $TEST_DIR/test_graphiti_concurrent_agents.py -v
            ;;
            
        temporal)
            print_color "$BLUE" "Running temporal query tests..."
            pytest $TEST_DIR/test_graphiti_temporal_queries.py -v
            ;;
            
        reranking)
            print_color "$BLUE" "Running reranking tests..."
            pytest $TEST_DIR/test_graphiti_reranking.py -v
            ;;
            
        benchmark)
            print_color "$BLUE" "Running benchmark tests only..."
            pytest $TEST_DIR -m benchmark --benchmark-only -v
            ;;
            
        integration)
            print_color "$BLUE" "Running all integration tests..."
            pytest $TEST_DIR -m integration -v
            ;;
            
        slow)
            print_color "$BLUE" "Running slow tests..."
            pytest $TEST_DIR -m slow -v
            ;;
            
        all)
            print_color "$BLUE" "Running all tests..."
            pytest $TEST_DIR -v
            ;;
            
        coverage)
            print_color "$BLUE" "Running tests with coverage..."
            pytest $TEST_DIR --cov=$TEST_DIR --cov-report=html --cov-report=term
            print_color "$GREEN" "Coverage report saved to htmlcov/index.html"
            ;;
            
        help|--help|-h)
            echo "Neo4j Graphiti Test Runner"
            echo ""
            echo "Usage: ./test.sh [suite]"
            echo ""
            echo "Available test suites:"
            echo "  quick       - Quick smoke tests"
            echo "  search      - Search performance tests"
            echo "  episode     - Episode processing tests"
            echo "  concurrent  - Concurrent agent tests"
            echo "  temporal    - Temporal query tests"
            echo "  reranking   - Reranking and proximity tests"
            echo "  benchmark   - Performance benchmark tests only"
            echo "  integration - All integration tests"
            echo "  slow        - Long-running tests"
            echo "  all         - All tests (default)"
            echo "  coverage    - Run with coverage report"
            echo "  help        - Show this help message"
            echo ""
            echo "Examples:"
            echo "  ./test.sh              # Run all tests"
            echo "  ./test.sh quick        # Run quick smoke tests"
            echo "  ./test.sh benchmark    # Run benchmarks only"
            echo "  ./test.sh coverage     # Run with coverage"
            exit 0
            ;;
            
        *)
            print_color "$RED" "Unknown test suite: $suite"
            echo "Run './test.sh help' for available options"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    print_color "$GREEN" "═══════════════════════════════════════"
    print_color "$GREEN" "   Neo4j Graphiti Test Suite"
    print_color "$GREEN" "═══════════════════════════════════════"
    echo ""
    
    # Check dependencies
    if [[ "$SUITE" != "help" && "$SUITE" != "--help" && "$SUITE" != "-h" ]]; then
        # Check if we're in the right directory
        if [ ! -d "$TEST_DIR" ]; then
            print_color "$RED" "Error: Test directory not found. Run from project root."
            exit 1
        fi
        
        # Check Neo4j
        check_neo4j
        
        # Install dependencies if needed
        if ! python -c "import graphiti_core" 2>/dev/null; then
            install_deps
        fi
        
        echo ""
        print_color "$YELLOW" "Running test suite: $SUITE"
        echo ""
        
        # Run the tests
        run_tests "$SUITE"
        
        # Print summary
        echo ""
        if [ $? -eq 0 ]; then
            print_color "$GREEN" "═══════════════════════════════════════"
            print_color "$GREEN" "   All tests passed! ✓"
            print_color "$GREEN" "═══════════════════════════════════════"
        else
            print_color "$RED" "═══════════════════════════════════════"
            print_color "$RED" "   Some tests failed ✗"
            print_color "$RED" "═══════════════════════════════════════"
        fi
    else
        run_tests "$SUITE"
    fi
}

# Run main function
main