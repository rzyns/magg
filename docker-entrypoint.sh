#!/bin/bash
# Docker entrypoint script for Magg with dual-mode SSL support

# Function to validate PEM file format
validate_pem() {
    local file="$1"
    local file_type="$2"
    
    if ! grep -q "-----BEGIN" "$file" 2>/dev/null; then
        echo "SSL: Warning - $file_type file may not be a valid PEM format"
        return 1
    fi
    return 0
}

# Function to setup SSL certificates
setup_ssl() {
    local ssl_enabled=false
    local ssl_mode=""
    
    # Check for partial configuration issues
    local has_host_key=false
    local has_host_cert=false
    local has_legacy_key=false
    local has_legacy_cert=false
    
    # Check host path mode files
    [ -f "/ssl/key.pem" ] && [ -s "/ssl/key.pem" ] && has_host_key=true
    [ -f "/ssl/cert.pem" ] && [ -s "/ssl/cert.pem" ] && has_host_cert=true
    
    # Check legacy mode files
    [ -n "$MAGG_SSL_KEYFILE" ] && [ -f "$MAGG_SSL_KEYFILE" ] && [ -s "$MAGG_SSL_KEYFILE" ] && has_legacy_key=true
    [ -n "$MAGG_SSL_CERTFILE" ] && [ -f "$MAGG_SSL_CERTFILE" ] && [ -s "$MAGG_SSL_CERTFILE" ] && has_legacy_cert=true
    
    # Mode 1: New host path approach (individual file mounts at /ssl/*)
    if [ "$has_host_key" = true ] && [ "$has_host_cert" = true ]; then
        # Validate PEM format
        validate_pem "/ssl/key.pem" "Private key"
        validate_pem "/ssl/cert.pem" "Certificate"
        
        export MAGG_SSL_KEYFILE="/ssl/key.pem"
        export MAGG_SSL_CERTFILE="/ssl/cert.pem"
        ssl_enabled=true
        ssl_mode="host path mounts"
        echo "SSL: Using certificates from host path mounts at /ssl/"
        
    elif [ "$has_host_key" = true ] && [ "$has_host_cert" = false ]; then
        echo "SSL: ERROR - Private key found at /ssl/key.pem but certificate missing at /ssl/cert.pem"
        echo "SSL: Both certificate files must be provided for SSL to work"
        
    elif [ "$has_host_key" = false ] && [ "$has_host_cert" = true ]; then
        echo "SSL: ERROR - Certificate found at /ssl/cert.pem but private key missing at /ssl/key.pem"
        echo "SSL: Both certificate files must be provided for SSL to work"
    fi
    
    # Mode 2: Legacy directory mount approach (backward compatibility)
    # Only check this if Mode 1 didn't find valid certificates
    if [ "$ssl_enabled" = false ]; then
        if [ "$has_legacy_key" = true ] && [ "$has_legacy_cert" = true ]; then
            # Validate PEM format
            validate_pem "$MAGG_SSL_KEYFILE" "Private key"
            validate_pem "$MAGG_SSL_CERTFILE" "Certificate"
            
            ssl_enabled=true
            ssl_mode="directory mount (legacy)"
            echo "SSL: Using certificates from directory mount"
            echo "SSL: Key: ${MAGG_SSL_KEYFILE##*/}, Cert: ${MAGG_SSL_CERTFILE##*/}"
            
        elif [ "$has_legacy_key" = true ] && [ "$has_legacy_cert" = false ]; then
            echo "SSL: ERROR - Private key configured but certificate missing"
            echo "SSL: MAGG_SSL_KEYFILE is set but MAGG_SSL_CERTFILE is not valid"
            
        elif [ "$has_legacy_key" = false ] && [ "$has_legacy_cert" = true ]; then
            echo "SSL: ERROR - Certificate configured but private key missing"
            echo "SSL: MAGG_SSL_CERTFILE is set but MAGG_SSL_KEYFILE is not valid"
            
        elif [ -n "$MAGG_SSL_KEYFILE" ] || [ -n "$MAGG_SSL_CERTFILE" ]; then
            # Environment variables set but files not found
            if [ -n "$MAGG_SSL_KEYFILE" ] && [ ! -f "$MAGG_SSL_KEYFILE" ]; then
                echo "SSL: Warning - MAGG_SSL_KEYFILE set but file not found: $MAGG_SSL_KEYFILE"
            fi
            if [ -n "$MAGG_SSL_CERTFILE" ] && [ ! -f "$MAGG_SSL_CERTFILE" ]; then
                echo "SSL: Warning - MAGG_SSL_CERTFILE set but file not found: $MAGG_SSL_CERTFILE"
            fi
        fi
    fi
    
    if [ "$ssl_enabled" = true ]; then
        echo "SSL: Enabled using $ssl_mode"
        return 0
    else
        echo "SSL: Disabled (no valid certificates found)"
        return 1
    fi
}

# Build the base command
CMD="magg serve --http --host 0.0.0.0 --port 8000"

# Setup SSL if available
if setup_ssl; then
    CMD="$CMD --ssl-keyfile $MAGG_SSL_KEYFILE --ssl-certfile $MAGG_SSL_CERTFILE"
    echo "Starting Magg server with SSL/TLS support on https://0.0.0.0:8000"
else
    echo "Starting Magg server without SSL/TLS (HTTP only) on http://0.0.0.0:8000"
fi

# Execute the command with any additional arguments
exec $CMD "$@"