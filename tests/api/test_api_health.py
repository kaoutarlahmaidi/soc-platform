import requests
import pytest

def test_manager_api_health():
    """Test Wazuh Manager API health endpoint"""
    try:
        response = requests.get("https://localhost:55000/manager/info", verify=False, timeout=10)
        assert response.status_code in [200, 401, 403]
    except requests.exceptions.SSLError:
        # If SSL fails completely, try to see if the port is at least listening
        import socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        result = sock.connect_ex(('localhost', 55000))
        sock.close()
        assert result == 0, "API port 55000 is not accessible"

def test_indexer_api_health():
    """Test Wazuh Indexer API health"""
    response = requests.get("https://localhost:9200", verify=False, timeout=10)
    assert response.status_code in [200, 401]
