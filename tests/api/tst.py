import requests
import pytest

def test_manager_api_health():
    """Test Wazuh Manager API health endpoint"""
    response = requests.get("https://localhost:55000", verify=False, timeout=10)
    assert response.status_code in [200, 401, 403]
    
def test_indexer_api_health():
    """Test Wazuh Indexer API health"""  
    response = requests.get("https://localhost:9200", verify=False, timeout=10)
    assert response.status_code in [200, 401]
