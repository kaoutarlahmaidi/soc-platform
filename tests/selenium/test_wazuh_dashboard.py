import pytest
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options

def test_dashboard_https():
    options = Options()
    options.add_argument("--ignore-certificate-errors")
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    
    driver = webdriver.Chrome(options=options)
    try:
        driver.get("https://localhost:443")
        WebDriverWait(driver, 10).until(
            lambda d: d.execute_script("return document.readyState") == "complete"
        )
        assert "https://" in driver.current_url
        print("Dashboard HTTPS test passed")
    finally:
        driver.quit()

def test_login_form():
    options = Options()
    options.add_argument("--ignore-certificate-errors")
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    
    driver = webdriver.Chrome(options=options)
    try:
        driver.get("https://localhost:443")
        wait = WebDriverWait(driver, 10)
        
        # Check page title
        assert "Wazuh" in driver.title or "OpenSearch" in driver.title
        
        # Check for login form elements
        username_field = wait.until(EC.presence_of_element_located(
            (By.CSS_SELECTOR, 'input[type="text"], input[name="username"]')
        ))
        password_field = driver.find_element(By.CSS_SELECTOR, 'input[type="password"]')
        
        assert username_field is not None
        assert password_field is not None
        print("Login form elements found")
    finally:
        driver.quit()
