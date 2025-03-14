import os
from flask import Flask #, render_template, request, redirect, url_for
from datetime import datetime
from flask_caching import Cache
import redis
    
app = Flask(__name__)

app.config['CACHE_TYPE'] = 'redis'
app.config['CACHE_REDIS_HOST'] = 'endpoint-redis'
app.config['CACHE_REDIS_PORT'] = 6379
app.config['CACHE_DEFAULT_TIMEOUT'] = 3000
cache = Cache(app)

from routes import *

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80, debug=True)