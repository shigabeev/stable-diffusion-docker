#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install sysbench without sudo
install_sysbench() {
    echo "sysbench is not installed. Attempting to install..."
    if command_exists apt-get; then
        apt-get update && apt-get install -y sysbench
    elif command_exists yum; then
        yum install -y epel-release && yum install -y sysbench
    else
        echo "Unable to install sysbench. Package manager not recognized."
        return 1
    fi
}

# Check for AVX support
check_avx() {
    if grep -q avx /proc/cpuinfo; then
        echo "AVX support: Yes"
    else
        echo "AVX support: No (This CPU might be too old for your needs)"
    fi
}

# Get CPU model and core count
get_cpu_info() {
    cpu_model=$(grep "model name" /proc/cpuinfo | head -n 1 | cut -d ':' -f 2 | sed 's/^[ \t]*//')
    cpu_cores=$(grep -c ^processor /proc/cpuinfo)
    cpu_freq=$(lscpu | grep "CPU MHz" | awk '{print $3}')
    echo "CPU Model: $cpu_model"
    echo "CPU Cores: $cpu_cores"
    echo "CPU Frequency: $cpu_freq MHz"
}

# Perform CPU benchmark
benchmark_cpu() {
    if ! command_exists sysbench; then
        install_sysbench
    fi
    
    if command_exists sysbench; then
        echo "Performing CPU benchmark..."
        result=$(sysbench --test=cpu --cpu-max-prime=20000 --threads=4 --time=30 run)
        eps=$(echo "$result" | grep "events per second" | awk '{print $4}')
        latency=$(echo "$result" | grep "avg:" | awk '{print $4}')
        
        echo "Benchmark results:"
        echo "  Events per second: $eps"
        echo "  Average latency: $latency ms"
        
        # Rough performance categorization
        if (( $(echo "$eps > 3000" | bc -l) )); then
            echo "  Performance category: Excellent"
        elif (( $(echo "$eps > 2000" | bc -l) )); then
            echo "  Performance category: Good"
        elif (( $(echo "$eps > 1000" | bc -l) )); then
            echo "  Performance category: Average"
        else
            echo "  Performance category: Below Average"
        fi
    else
        echo "sysbench installation failed. Skipping CPU benchmark."
    fi
}

# Main function
main() {
    echo "RunPod CPU Check Script"
    echo "----------------------"
    
    check_avx
    get_cpu_info
    benchmark_cpu
    
    echo "----------------------"
    echo "Recommendations:"
    if ! grep -q avx /proc/cpuinfo; then
        echo "- This CPU lacks AVX support. Consider requesting a different pod."
    fi
    echo "- If performance is unsatisfactory, try restarting the pod or contacting RunPod support."
    echo "- You may want to adjust your datacenter preferences based on these results."
}

# Run the main function
main