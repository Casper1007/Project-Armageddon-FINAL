# Honors Lab 2B: Origin-Driven Caching Endpoints
@app.route('/api/public-feed', methods=['GET'])
def public_feed():
    """Public, cacheable endpoint: returns server time and a message."""
    from datetime import datetime
    import random
    messages = [
        "The Force will be with you. Always.",
        "Do. Or do not. There is no try.",
        "I find your lack of faith disturbing.",
        "Never tell me the odds!",
        "The ability to speak does not make you intelligent."
    ]
    response = jsonify({
        "server_time_utc": datetime.utcnow().isoformat() + 'Z',
        "message_of_the_minute": random.choice(messages)
    })
    # Cache-Control: public, s-maxage=30, max-age=0
    response.headers['Cache-Control'] = 'public, s-maxage=30, max-age=0'
    return response


# Private, never-cache endpoint
@app.route('/api/list', methods=['GET'])
def api_list():
    """Private, never-cache endpoint: returns all notes (or dummy data)."""
    # You can use get_all_notes() or return dummy data for demonstration
    try:
        # result = get_all_notes()  # Uncomment if you want real data
        result = {"notes": ["secret1", "secret2", "secret3"]}  # Dummy data
        response = jsonify(result)
        response.headers['Cache-Control'] = 'private, no-store'
        return response
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500
#!/usr/bin/env python3
"""
EC2 → RDS Lab Application
Demonstrates secure database connectivity using IAM roles and Secrets Manager
"""

import json
import logging
import sys
import traceback
from datetime import datetime

import boto3
import mysql.connector
from flask import Flask, jsonify, request

# ============================================================================
# Configuration & Logging
# ============================================================================

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/rds-app.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# ============================================================================
# AWS Secrets Manager Integration
# ============================================================================

def get_db_credentials():
    """
    Retrieve database credentials from AWS Secrets Manager.
    Uses IAM role attached to EC2 instance (no static credentials in code).
    """
    try:
        secrets_client = boto3.client('secretsmanager', region_name='us-east-1')
        response = secrets_client.get_secret_value(SecretId='lab1a/rds/mysql')
        
        if 'SecretString' in response:
            secret = json.loads(response['SecretString'])
            logger.info(f"Successfully retrieved credentials for user: {secret.get('username')}")
            return secret
        else:
            logger.error("Secret does not contain SecretString")
            raise Exception("Invalid secret format")
            
    except Exception as e:
        logger.error(f"Failed to retrieve credentials from Secrets Manager: {str(e)}")
        raise


def get_db_connection():
    """
    Establish a connection to RDS MySQL using retrieved credentials.
    """
    try:
        creds = get_db_credentials()
        connection = mysql.connector.connect(
            host=creds['host'],
            user=creds['username'],
            password=creds['password'],
            database=creds['dbname'],
            port=creds['port'],
            autocommit=True
        )
        logger.info(f"Connected to RDS at {creds['host']}:{creds['port']}")
        return connection
    except Exception as e:
        logger.error(f"Failed to connect to database: {str(e)}")
        raise


# ============================================================================
# Database Operations
# ============================================================================

def init_database():
    """
    Initialize the database with a simple notes table.
    """
    try:
        connection = get_db_connection()
        cursor = connection.cursor()
        
        # Create notes table if it doesn't exist
        create_table_sql = """
        CREATE TABLE IF NOT EXISTS notes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            note TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """
        
        cursor.execute(create_table_sql)
        logger.info("Database initialized successfully")
        cursor.close()
        connection.close()
        
        return {"status": "success", "message": "Database initialized"}
    except Exception as e:
        logger.error(f"Database initialization failed: {str(e)}")
        return {"status": "error", "message": str(e)}, 500


def insert_note(note_text):
    """
    Insert a note into the database.
    """
    try:
        connection = get_db_connection()
        cursor = connection.cursor()
        
        insert_sql = "INSERT INTO notes (note) VALUES (%s);"
        cursor.execute(insert_sql, (note_text,))
        connection.commit()
        
        logger.info(f"Note inserted: {note_text}")
        cursor.close()
        connection.close()
        
        return {"status": "success", "message": "Note added"}
    except Exception as e:
        logger.error(f"Insert failed: {str(e)}")
        return {"status": "error", "message": str(e)}, 500


def get_all_notes():
    """
    Retrieve all notes from the database.
    """
    try:
        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)
        
        cursor.execute("SELECT id, note, created_at FROM notes ORDER BY created_at DESC;")
        notes = cursor.fetchall()
        
        logger.info(f"Retrieved {len(notes)} notes from database")
        cursor.close()
        connection.close()
        
        return {"status": "success", "notes": notes}
    except Exception as e:
        logger.error(f"Retrieve failed: {str(e)}")
        return {"status": "error", "message": str(e)}, 500


# ============================================================================
# Flask Routes
# ============================================================================

@app.route('/', methods=['GET'])
def index():
    """Health check and documentation."""
    return jsonify({
        "service": "EC2 → RDS Integration Lab",
        "status": "running",
        "endpoints": {
            "GET /": "This message",
            "POST /init": "Initialize database",
            "GET /list": "List all notes",
            "POST /add?note=YOUR_NOTE": "Add a note"
        }
    })


@app.route('/init', methods=['POST', 'GET'])
def init():
    """Initialize the database schema."""
    logger.info("Initialize endpoint called")
    result = init_database()
    if isinstance(result, tuple):
        return jsonify(result[0]), result[1]
    return jsonify(result)


@app.route('/add', methods=['GET', 'POST'])
def add_note():
    """Add a note to the database."""
    try:
        # Get note from query parameter or form data
        note = request.args.get('note') or request.form.get('note')
        
        if not note:
            return jsonify({"status": "error", "message": "Missing 'note' parameter"}), 400
        
        logger.info(f"Add note endpoint called with: {note}")
        result = insert_note(note)
        
        if isinstance(result, tuple):
            return jsonify(result[0]), result[1]
        return jsonify(result)
    except Exception as e:
        logger.error(f"Add endpoint error: {str(e)}\n{traceback.format_exc()}")
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route('/list', methods=['GET'])
def list_notes():
    """Retrieve and list all notes from the database."""
    try:
        logger.info("List endpoint called")
        result = get_all_notes()
        response = jsonify(result[0]) if isinstance(result, tuple) else jsonify(result)
        # Add Cache-Control header for safe caching
        response.headers['Cache-Control'] = 'public, max-age=30'
        return response
    except Exception as e:
        logger.error(f"List endpoint error: {str(e)}\n{traceback.format_exc()}")
        return jsonify({"status": "error", "message": str(e)}), 500


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint for load balancers."""
    try:
        # Try to get credentials to verify IAM/Secrets Manager access
        creds = get_db_credentials()
        return jsonify({
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "database_host": creds['host']
        })
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 503


@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors."""
    return jsonify({"status": "error", "message": "Endpoint not found"}), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors."""
    logger.error(f"Internal server error: {str(error)}")
    return jsonify({"status": "error", "message": "Internal server error"}), 500


# ============================================================================
# Main
# ============================================================================

if __name__ == '__main__':
    logger.info("=" * 80)
    logger.info("EC2 → RDS Lab Application Starting")
    logger.info("=" * 80)
    
    try:
        # Verify we can access Secrets Manager
        logger.info("Testing Secrets Manager access...")
        creds = get_db_credentials()
        logger.info(f"✓ Secrets Manager access confirmed - DB host: {creds['host']}")
    except Exception as e:
        logger.error(f"✗ Secrets Manager access failed: {str(e)}")
        logger.error("Cannot proceed without database credentials")
        sys.exit(1)
    
    # Start Flask app
    logger.info("Starting Flask application on 0.0.0.0:80")
    app.run(host='0.0.0.0', port=80, debug=False)
