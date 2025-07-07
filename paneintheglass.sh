#!/bin/bash

# Pane in the Glass - Complete Project Setup Script
# Creates a modern stained glass portfolio website with admin portal

set -e

PROJECT_DIR="$HOME/Programming/paneintheglass"

echo "🎨 Creating Pane in the Glass portfolio website..."
echo "📍 Project location: $PROJECT_DIR"

# Create project directory structure
mkdir -p "$PROJECT_DIR"/{static/uploads/thumbnails,templates,instance}
cd "$PROJECT_DIR"

echo "📁 Created directory structure"

# Create pyproject.toml
cat >pyproject.toml <<'EOF'
[project]
name = "paneintheglass"
version = "0.1.0"
description = "Stained Glass Portfolio Website"
authors = [
    {name = "Artist", email = "artist@paneintheglass.com"}
]
readme = "README.md"
requires-python = ">=3.11"
dependencies = [
    "flask>=2.3.3",
    "flask-sqlalchemy>=3.0.5",
    "flask-migrate>=4.0.5",
    "pillow>=10.0.0",
    "python-dotenv>=1.0.0",
    "gunicorn>=21.2.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0.0",
    "black>=23.0.0",
    "ruff>=0.1.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.ruff]
line-length = 88
target-version = "py311"

[tool.black]
line-length = 88
target-version = ['py311']
EOF

echo "📦 Created pyproject.toml"

# Create .env file
cat >.env <<'EOF'
# Flask Configuration
FLASK_APP=app.py
FLASK_ENV=development
SECRET_KEY=dev-secret-key-change-in-production

# Database Configuration (SQLite for easy setup)
DATABASE_URL=sqlite:///instance/app.db

# Admin Configuration
ADMIN_PASSWORD=glassart2024

# Upload Configuration
UPLOAD_FOLDER=static/uploads
MAX_CONTENT_LENGTH=16777216

# Development settings
DEBUG=True
EOF

echo "🔧 Created .env file"

# Create main Flask application
cat >app.py <<'EOF'
import os
import uuid
from datetime import datetime
from werkzeug.utils import secure_filename
from werkzeug.security import check_password_hash, generate_password_hash
from flask import Flask, request, jsonify, render_template, send_from_directory, session
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from PIL import Image
import secrets
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Initialize Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', secrets.token_hex(16))

# Database configuration
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'sqlite:///instance/app.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# File upload configuration
app.config['UPLOAD_FOLDER'] = os.environ.get('UPLOAD_FOLDER', 'static/uploads')
app.config['MAX_CONTENT_LENGTH'] = int(os.environ.get('MAX_CONTENT_LENGTH', 16 * 1024 * 1024))
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}

# Admin password
ADMIN_PASSWORD_HASH = generate_password_hash(os.environ.get('ADMIN_PASSWORD', 'glassart2024'))

# Initialize extensions
db = SQLAlchemy(app)
migrate = Migrate(app, db)

# Database Models
class PortfolioImage(db.Model):
    __tablename__ = 'portfolio_images'
    
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text)
    filename = db.Column(db.String(255), nullable=False, unique=True)
    original_filename = db.Column(db.String(255), nullable=False)
    file_size = db.Column(db.Integer)
    width = db.Column(db.Integer)
    height = db.Column(db.Integer)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    is_featured = db.Column(db.Boolean, default=False)
    display_order = db.Column(db.Integer, default=0)
    
    def to_dict(self):
        return {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'filename': self.filename,
            'original_filename': self.original_filename,
            'f[48;30;95;1200;1710tile_size': self.file_size,
            'width': self.width,
            'height': self.height,
            'created_at': self.created_at.isoformat(),
            'is_featured': self.is_featured,
            'display_order': self.display_order,
            'image_url': f'/uploads/{self.filename}',
            'thumbnail_url': f'/uploads/thumbnails/{self.filename}'
        }

# Utility Functions
def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def generate_unique_filename(original_filename):
    extension = original_filename.rsplit('.', 1)[1].lower()
    return f"{uuid.uuid4().hex}.{extension}"

def create_thumbnail(image_path, thumbnail_path, size=(400, 400)):
    try:
        with Image.open(image_path) as img:
            if img.mode in ('RGBA', 'LA', 'P'):
                background = Image.new('RGB', img.size, (255, 255, 255))
                if img.mode == 'P':
                    img = img.convert('RGBA')
                background.paste(img, mask=img.split()[-1] if img.mode == 'RGBA' else None)
                img = background
            
            img.thumbnail(size, Image.Resampling.LANCZOS)
            thumb = Image.new('RGB', size, (255, 255, 255))
            thumb_w, thumb_h = img.size
            offset = ((size[0] - thumb_w) // 2, (size[1] - thumb_h) // 2)
            thumb.paste(img, offset)
            thumb.save(thumbnail_path, 'JPEG', quality=85)
            return True
    except Exception as e:
        print(f"Error creating thumbnail: {e}")
        return False

def ensure_upload_directories():
    upload_dir = app.config['UPLOAD_FOLDER']
    thumbnail_dir = os.path.join(upload_dir, 'thumbnails')
    os.makedirs(upload_dir, exist_ok=True)
    os.makedirs(thumbnail_dir, exist_ok=True)
    os.makedirs('instance', exist_ok=True)

# Routes
@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/portfolio')
def get_portfolio():
    images = PortfolioImage.query.order_by(
        PortfolioImage.display_order.asc(),
        PortfolioImage.created_at.desc()
    ).all()
    return jsonify([img.to_dict() for img in images])

@app.route('/api/admin/login', methods=['POST'])
def admin_login():
    data = request.get_json()
    password = data.get('password', '')
    
    if check_password_hash(ADMIN_PASSWORD_HASH, password):
        session['admin_logged_in'] = True
        return jsonify({'success': True, 'message': 'Login successful'})
    else:
        return jsonify({'success': False, 'message': 'Invalid password'}), 401

def admin_required(f):
    from functools import wraps
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('admin_logged_in'):
            return jsonify({'error': 'Admin login required'}), 401
        return f(*args, **kwargs)
    return decorated_function

@app.route('/api/admin/upload', methods=['POST'])
@admin_required
def upload_image():
    if 'image' not in request.files:
        return jsonify({'error': 'No image file provided'}), 400
    
    file = request.files['image']
    title = request.form.get('title', '').strip()
    description = request.form.get('description', '').strip()
    is_featured = request.form.get('is_featured', 'false').lower() == 'true'
    
    if file.filename == '' or not title:
        return jsonify({'error': 'File and title are required'}), 400
    
    if file and allowed_file(file.filename):
        ensure_upload_directories()
        
        original_filename = secure_filename(file.filename)
        unique_filename = generate_unique_filename(original_filename)
        
        image_path = os.path.join(app.config['UPLOAD_FOLDER'], unique_filename)
        file.save(image_path)
        
        try:
            with Image.open(image_path) as img:
                width, height = img.size
            file_size = os.path.getsize(image_path)
        except Exception as e:
            os.remove(image_path)
            return jsonify({'error': f'Invalid image file: {str(e)}'}), 400
        
        thumbnail_path = os.path.join(app.config['UPLOAD_FOLDER'], 'thumbnails', unique_filename)
        create_thumbnail(image_path, thumbnail_path)
        
        portfolio_image = PortfolioImage(
            title=title,
            description=description,
            filename=unique_filename,
            original_filename=original_filename,
            file_size=file_size,
            width=width,
            height=height,
            is_featured=is_featured
        )
        
        try:
            db.session.add(portfolio_image)
            db.session.commit()
            return jsonify({
                'success': True,
                'message': 'Image uploaded successfully',
                'image': portfolio_image.to_dict()
            })
        except Exception as e:
            db.session.rollback()
            if os.path.exists(image_path):
                os.remove(image_path)
            if os.path.exists(thumbnail_path):
                os.remove(thumbnail_path)
            return jsonify({'error': f'Database error: {str(e)}'}), 500
    
    return jsonify({'error': 'Invalid file type'}), 400

@app.route('/api/admin/images')
@admin_required
def get_admin_images():
    images = PortfolioImage.query.order_by(PortfolioImage.created_at.desc()).all()
    return jsonify([img.to_dict() for img in images])

@app.route('/api/admin/images/<int:image_id>', methods=['DELETE'])
@admin_required
def delete_image(image_id):
    image = PortfolioImage.query.get_or_404(image_id)
    
    image_path = os.path.join(app.config['UPLOAD_FOLDER'], image.filename)
    thumbnail_path = os.path.join(app.config['UPLOAD_FOLDER'], 'thumbnails', image.filename)
    
    if os.path.exists(image_path):
        os.remove(image_path)
    if os.path.exists(thumbnail_path):
        os.remove(thumbnail_path)
    
    db.session.delete(image)
    db.session.commit()
    
    return jsonify({'success': True, 'message': 'Image deleted successfully'})

@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

@app.route('/uploads/thumbnails/<filename>')
def uploaded_thumbnail(filename):
    thumbnail_dir = os.path.join(app.config['UPLOAD_FOLDER'], 'thumbnails')
    return send_from_directory(thumbnail_dir, filename)

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    db.session.rollback()
    return jsonify({'error': 'Internal server error'}), 500

# Create tables and directories
with app.app_context():
    db.create_all()
    ensure_upload_directories()

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)
EOF

echo "🐍 Created Flask application (app.py)"

# Create HTML template
cat >templates/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Pane in the Glass - Artisan Stained Glass</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        glass: {
                            50: '#f0fdf4', 100: '#dcfce7', 200: '#bbf7d0', 300: '#86efac',
                            400: '#4ade80', 500: '#22c55e', 600: '#16a34a', 700: '#15803d',
                            800: '#166534', 900: '#14532d'
                        }
                    }
                }
            }
        }
    </script>
    <style>
        .glass-pattern {
            background: linear-gradient(45deg, rgba(34, 197, 94, 0.1) 25%, transparent 25%), 
                        linear-gradient(-45deg, rgba(34, 197, 94, 0.1) 25%, transparent 25%), 
                        linear-gradient(45deg, transparent 75%, rgba(34, 197, 94, 0.1) 75%), 
                        linear-gradient(-45deg, transparent 75%, rgba(34, 197, 94, 0.1) 75%);
            background-size: 20px 20px;
        }
        .glass-shimmer {
            background: linear-gradient(135deg, #22c55e 0%, #16a34a 50%, #15803d 100%);
            background-size: 200% 200%;
            animation: shimmer 3s ease-in-out infinite;
        }
        @keyframes shimmer {
            0%, 100% { background-position: 0% 50%; }
            50% { background-position: 100% 50%; }
        }
        .image-hover {
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        .image-hover:hover {
            transform: translateY(-5px) scale(1.02);
            box-shadow: 0 20px 40px rgba(34, 197, 94, 0.3);
        }
    </style>
</head>
<body class="bg-gray-50">
    <!-- Navigation -->
    <nav class="bg-white shadow-lg sticky top-0 z-50">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="flex justify-between items-center h-16">
                <div class="flex items-center space-x-2">
                    <div class="w-8 h-8 glass-shimmer rounded-full"></div>
                    <h1 class="text-2xl font-bold text-glass-800">Pane in the Glass</h1>
                </div>
                <div class="hidden md:flex space-x-8">
                    <a href="#home" class="text-gray-700 hover:text-glass-600 transition-colors">Home</a>
                    <a href="#portfolio" class="text-gray-700 hover:text-glass-600 transition-colors">Portfolio</a>
                    <a href="#about" class="text-gray-700 hover:text-glass-600 transition-colors">About</a>
                    <a href="#contact" class="text-gray-700 hover:text-glass-600 transition-colors">Contact</a>
                    <button onclick="showAdminLogin()" class="text-glass-600 hover:text-glass-800 transition-colors">Admin</button>
                </div>
            </div>
        </div>
    </nav>

    <!-- Hero Section -->
    <section id="home" class="glass-pattern py-20">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
            <h2 class="text-5xl md:text-6xl font-bold text-gray-800 mb-6">
                Artisan <span class="text-glass-600">Stained Glass</span>
            </h2>
            <p class="text-xl text-gray-600 mb-8 max-w-3xl mx-auto">
                Handcrafted stained glass art that transforms light into poetry. 
                Each piece tells a story through color, texture, and the dance of illumination.
            </p>
            <button onclick="scrollToPortfolio()" class="bg-glass-600 text-white px-8 py-4 rounded-full text-lg font-semibold hover:bg-glass-700 transition-colors shadow-lg">
                View Portfolio
            </button>
        </div>
    </section>

    <!-- Portfolio Section -->
    <section id="portfolio" class="py-20 bg-white">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <h2 class="text-4xl font-bold text-center text-gray-800 mb-12">Featured Works</h2>
            
            <div id="portfolio-loading" class="text-center py-20">
                <div class="glass-shimmer w-12 h-12 rounded-full mx-auto mb-4"></div>
                <p class="text-glass-600">Loading portfolio...</p>
            </div>
            
            <div id="portfolio-grid" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 hidden"></div>
            
            <div id="portfolio-empty" class="text-center py-20 hidden">
                <p class="text-gray-600 text-lg">No portfolio items available yet.</p>
                <p class="text-gray-500">Click "Admin" to upload your first image!</p>
            </div>
        </div>
    </section>

    <!-- About Section -->
    <section id="about" class="py-20 bg-gray-100">
        <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="text-center mb-12">
                <h2 class="text-4xl font-bold text-gray-800 mb-6">About the Artist</h2>
                <div class="w-32 h-32 mx-auto rounded-full bg-gradient-to-br from-glass-400 to-glass-600 mb-6"></div>
                <p class="text-lg text-gray-700 leading-relaxed">
                    With over two decades of experience in the ancient art of stained glass, 
                    I create pieces that celebrate both traditional techniques and contemporary vision. 
                    Each window, panel, and sculpture is meticulously crafted to capture and transform 
                    natural light into something magical.
                </p>
            </div>
        </div>
    </section>

    <!-- Contact Section -->
    <section id="contact" class="py-20 bg-white">
        <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
            <h2 class="text-4xl font-bold text-gray-800 mb-8">Get in Touch</h2>
            <p class="text-lg text-gray-600 mb-8">
                Ready to commission a custom piece or have questions about my work?
            </p>
            <div class="flex flex-col md:flex-row justify-center items-center space-y-4 md:space-y-0 md:space-x-8">
                <a href="mailto:artist@paneintheglass.com" 
                   class="bg-glass-600 text-white px-6 py-3 rounded-full hover:bg-glass-700 transition-colors">
                    Email Me
                </a>
                <a href="tel:+1234567890" 
                   class="border-2 border-glass-600 text-glass-600 px-6 py-3 rounded-full hover:bg-glass-600 hover:text-white transition-colors">
                    Call Now
                </a>
            </div>
        </div>
    </section>

    <!-- Admin Login Modal -->
    <div id="admin-modal" class="fixed inset-0 bg-black bg-opacity-50 hidden z-50 flex items-center justify-center">
        <div class="bg-white rounded-xl p-8 max-w-md w-full mx-4">
            <h3 class="text-2xl font-bold text-gray-800 mb-6">Admin Access</h3>
            <div id="login-error" class="hidden bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4"></div>
            <form id="admin-form" onsubmit="handleAdminLogin(event)">
                <input type="password" id="admin-password" placeholder="Enter admin password"
                       class="w-full p-4 border-2 border-gray-300 rounded-lg mb-4 focus:border-glass-500 focus:outline-none">
                <div class="flex space-x-4">
                    <button type="submit" id="login-btn"
                            class="flex-1 bg-glass-600 text-white py-3 rounded-lg hover:bg-glass-700 transition-colors">
                        Login
                    </button>
                    <button type="button" onclick="hideAdminLogin()"
                            class="flex-1 border-2 border-gray-300 text-gray-700 py-3 rounded-lg hover:bg-gray-100 transition-colors">
                        Cancel
                    </button>
                </div>
            </form>
        </div>
    </div>

    <!-- Admin Panel -->
    <div id="admin-panel" class="fixed inset-0 bg-white hidden z-50 overflow-y-auto">
        <div class="min-h-screen bg-gray-100">
            <div class="bg-white shadow-sm">
                <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                    <div class="flex justify-between items-center h-16">
                        <h1 class="text-xl font-semibold text-gray-800">Portfolio Admin</h1>
                        <button onclick="hideAdminPanel()" 
                                class="text-gray-600 hover:text-gray-800 transition-colors">
                            ✕ Close
                        </button>
                    </div>
                </div>
            </div>

            <div class="max-w-4xl mx-auto p-8">
                <div class="bg-white rounded-xl shadow-lg p-8 mb-8">
                    <h2 class="text-2xl font-bold text-gray-800 mb-6">Upload New Image</h2>
                    <div id="upload-error" class="hidden bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4"></div>
                    <div id="upload-success" class="hidden bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded mb-4"></div>
                    
                    <form id="upload-form" onsubmit="handleImageUpload(event)">
                        <div class="mb-6">
                            <label class="block text-sm font-medium text-gray-700 mb-2">Image File</label>
                            <input type="file" id="image-file" accept="image/*" required
                                   class="w-full p-3 border-2 border-dashed border-gray-300 rounded-lg hover:border-glass-500 transition-colors">
                            <p class="text-sm text-gray-500 mt-1">Maximum file size: 16MB</p>
                        </div>
                        <div class="mb-6">
                            <label class="block text-sm font-medium text-gray-700 mb-2">Title</label>
                            <input type="text" id="image-title" required
                                   class="w-full p-3 border-2 border-gray-300 rounded-lg focus:border-glass-500 focus:outline-none">
                        </div>
                        <div class="mb-6">
                            <label class="block text-sm font-medium text-gray-700 mb-2">Description</label>
                            <textarea id="image-description" rows="3"
                                      class="w-full p-3 border-2 border-gray-300 rounded-lg focus:border-glass-500 focus:outline-none"></textarea>
                        </div>
                        <div class="mb-6">
                            <label class="flex items-center">
                                <input type="checkbox" id="is-featured" class="mr-2">
                                <span class="text-sm font-medium text-gray-700">Featured image</span>
                            </label>
                        </div>
                        <button type="submit" id="upload-btn"
                                class="bg-glass-600 text-white px-6 py-3 rounded-lg hover:bg-glass-700 transition-colors">
                            Upload Image
                        </button>
                    </form>
                </div>

                <div class="bg-white rounded-xl shadow-lg p-8">
                    <h2 class="text-2xl font-bold text-gray-800 mb-6">Current Portfolio</h2>
                    <div id="admin-loading" class="text-center py-10">
                        <div class="glass-shimmer w-8 h-8 rounded-full mx-auto mb-2"></div>
                        <p class="text-glass-600">Loading images...</p>
                    </div>
                    <div id="admin-portfolio-grid" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 hidden"></div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let portfolioImages = [];

        document.addEventListener('DOMContentLoaded', function() {
            loadPortfolio();
        });

        async function apiCall(url, options = {}) {
            const response = await fetch(url, {
                headers: { 'Content-Type': 'application/json', ...options.headers },
                ...options
            });
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            return await response.json();
        }

        async function loadPortfolio() {
            const loading = document.getElementById('portfolio-loading');
            const grid = document.getElementById('portfolio-grid');
            const empty = document.getElementById('portfolio-empty');
            
            try {
                const images = await apiCall('/api/portfolio');
                portfolioImages = images;
                
                loading.classList.add('hidden');
                
                if (images.length === 0) {
                    empty.classList.remove('hidden');
                } else {
                    grid.classList.remove('hidden');
                    renderPortfolioGrid(images, grid);
                }
            } catch (error) {
                loading.classList.add('hidden');
                empty.classList.remove('hidden');
            }
        }

        function renderPortfolioGrid(images, container) {
            container.innerHTML = images.map(image => `
                <div class="image-hover bg-white rounded-xl shadow-lg overflow-hidden">
                    <div class="h-64 overflow-hidden">
                        <img src="${image.thumbnail_url}" alt="${image.title}" 
                             class="w-full h-full object-cover" onerror="this.src='data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNDAwIiBoZWlnaHQ9IjQwMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48cmVjdCB3aWR0aD0iMTAwJSIgaGVpZ2h0PSIxMDAlIiBmaWxsPSIjZGRkIi8+PHRleHQgeD0iNTAlIiB5PSI1MCUiIGZvbnQtZmFtaWx5PSJBcmlhbCIgZm9udC1zaXplPSIxOCIgZmlsbD0iIzk5OSIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZHk9Ii4zZW0iPkltYWdlPC90ZXh0Pjwvc3ZnPg=='">
                    </div>
                    <div class="p-6">
                        <h3 class="text-xl font-semibold text-gray-800 mb-2">${image.title}</h3>
                        <p class="text-gray-600">${image.description || 'Beautiful stained glass artwork.'}</p>
                    </div>
                </div>
            `).join('');
        }

        function showAdminLogin() {
            document.getElementById('admin-modal').classList.remove('hidden');
            document.getElementById('admin-password').focus();
        }

        function hideAdminLogin() {
            document.getElementById('admin-modal').classList.add('hidden');
            document.getElementById('admin-password').value = '';
            document.getElementById('login-error').classList.add('hidden');
        }

        async function handleAdminLogin(event) {
            event.preventDefault();
            const password = document.getElementById('admin-password').value;
            const loginBtn = document.getElementById('login-btn');
            const errorDiv = document.getElementById('login-error');
            
            loginBtn.disabled = true;
            loginBtn.textContent = 'Logging in...';
            errorDiv.classList.add('hidden');
            
            try {
                const result = await apiCall('/api/admin/login', {
                    method: 'POST',
                    body: JSON.stringify({ password: password })
                });
                
                if (result.success) {
                    hideAdminLogin();
                    showAdminPanel();
                }
            } catch (error) {
                errorDiv.textContent = 'Login failed';
                errorDiv.classList.remove('hidden');
            } finally {
                loginBtn.disabled = false;
                loginBtn.textContent = 'Login';
            }
        }

        function showAdminPanel() {
            document.getElementById('admin-panel').classList.remove('hidden');
            loadAdminPortfolio();
        }

        function hideAdminPanel() {
            document.getElementById('admin-panel').classList.add('hidden');
        }

        async function loadAdminPortfolio() {
            const loading = document.getElementById('admin-loading');
            const grid = document.getElementById('admin-portfolio-grid');
            
            try {
                const images = await apiCall('/api/admin/images');
                loading.classList.add('hidden');
                grid.classList.remove('hidden');
                
                grid.innerHTML = images.map(image => `
                    <div class="bg-gray-100 rounded-lg p-4">
                        <div class="h-40 overflow-hidden rounded-lg mb-3">
                            <img src="${image.thumbnail_url}" alt="${image.title}" 
                                 class="w-full h-full object-cover">
                        </div>
                        <h3 class="font-semibold text-gray-800 mb-1">${image.title}</h3>
                        <p class="text-sm text-gray-600 mb-2">${image.description || 'No description'}</p>
                        <div class="flex items-center justify-between">
                            <span class="text-xs ${image.is_featured ? 'text-glass-600' : 'text-gray-400'}">
                                ${image.is_featured ? '⭐ Featured' : 'Not featured'}
                            </span>
                            <button onclick="deleteImage(${image.id})" 
                                    class="text-red-600 hover:text-red-800 text-sm">Delete</button>
                        </div>
                    </div>
                `).join('');
            } catch (error) {
                console.error('Failed to load admin portfolio:', error);
            }
        }

        async function handleImageUpload(event) {
            event.preventDefault();
            const form = document.getElementById('upload-form');
            const uploadBtn = document.getElementById('upload-btn');
            const errorDiv = document.getElementById('upload-error');
            const successDiv = document.getElementById('upload-success');
            
            errorDiv.classList.add('hidden');
            successDiv.classList.add('hidden');
            uploadBtn.disabled = true;
            uploadBtn.textContent = 'Uploading...';
            
            try {
                const formData = new FormData();
                formData.append('image', document.getElementById('image-file').files[0]);
                formData.append('title', document.getElementById('image-title').value);
                formData.append('description', document.getElementById('image-description').value);
                formData.append('is_featured', document.getElementById('is-featured').checked);
                
                const response = await fetch('/api/admin/upload', {
                    method: 'POST',
                    body: formData
                });
                
                const result = await response.json();
                
                if (result.success) {
                    successDiv.textContent = result.message;
                    successDiv.classList.remove('hidden');
                    form.reset();
                    loadAdminPortfolio();
                    loadPortfolio();
                } else {
                    throw new Error(result.error);
                }
            } catch (error) {
                errorDiv.textContent = error.message || 'Upload failed';
                errorDiv.classList.remove('hidden');
            } finally {
                uploadBtn.disabled = false;
                uploadBtn.textContent = 'Upload Image';
            }
        }

        async function deleteImage(imageId) {
            if (!confirm('Are you sure you want to delete this image?')) return;
            
            try {
                await apiCall(`/api/admin/images/${imageId}`, { method: 'DELETE' });
                loadAdminPortfolio();
                loadPortfolio();
            } catch (error) {
                alert('Failed to delete image: ' + error.message);
            }
        }

        function scrollToPortfolio() {
            document.getElementById('portfolio').scrollIntoView({ behavior: 'smooth' });
        }

        document.querySelectorAll('a[href^="#"]').forEach(anchor => {
            anchor.addEventListener('click', function (e) {
                e.preventDefault();
                const target = document.querySelector(this.getAttribute('href'));
                if (target) target.scrollIntoView({ behavior: 'smooth' });
            });
        });
    </script>
</body>
</html>
EOF

echo "🎨 Created HTML template"

# Create README
cat >README.md <<'EOF'
# 🎨 Pane in the Glass

Modern stained glass portfolio website with admin portal for easy image management.

## 🚀 Quick Start

```bash
# Install dependencies
uv sync

# Run the application
uv run python app.py
```

Visit http://localhost:5000
Admin password: `glassart2024`

## 🌐 Access

- **Website**: http://localhost:5000
- **Admin Panel**: Click "Admin" button, password: `glassart2024`

## 📁 Features

- Beautiful responsive design with green glass theme
- Password-protected admin portal
- Image upload with automatic thumbnails
- SQLite database (no external DB needed)
- Modern tech stack: Flask + Tailwind CSS

## 🔧 Admin Functions

1. Click "Admin" button on the site
2. Enter password: `glassart2024`
3. Upload images with titles and descriptions
4. Images automatically get thumbnails
5. Mark images as "featured"
6. Delete images as needed

## 🎨 Customization

### Change Colors
Edit the Tailwind config in `templates/index.html`:
```javascript
colors: {
    glass: {
        500: '#your-color-here',
        // ... other shades
    }
}
```

### Update Content
- Artist bio: Edit "About the Artist" section in template
- Contact info: Update email/phone in contact section
- Site title: Change "Pane in the Glass" throughout

## 🔐 Security

### Production Setup
1. Change admin password in `.env`:
   ```
   ADMIN_PASSWORD=your-secure-password
   ```

2. Generate secure secret key:
   ```
   SECRET_KEY=your-super-secret-key
   ```

## 🛠️ Tech Stack

- **Backend**: Flask + SQLAlchemy + SQLite
- **Frontend**: Tailwind CSS + Vanilla JavaScript  
- **Images**: Pillow for processing and thumbnails
- **Package Management**: uv for fast Python dependencies

Built with uv and ready for production deployment!
EOF

echo "📄 Created README.md"

# Install dependencies
echo "📦 Installing dependencies with uv..."
if command -v uv &>/dev/null; then
  uv sync
  echo "✅ Dependencies installed successfully!"
else
  echo "⚠️  uv not found. Install it with:"
  echo "   curl -LsSf https://astral.sh/uv/install.sh | sh"
  echo "   then run: uv sync"
fi

echo ""
echo "🎉 Project setup complete!"
echo ""
echo "📍 Project location: $PROJECT_DIR"
echo "🚀 To start the server:"
echo "   cd $PROJECT_DIR"
echo "   uv run python app.py"
echo ""
echo "🌐 Website: http://localhost:5000"
echo "🔑 Admin password: glassart2024"
echo ""
echo "📚 Next steps:"
echo "   1. Start the server with: uv run python app.py"
echo "   2. Visit http://localhost:5000"
echo "   3. Click 'Admin' to upload images"
echo "   4. Edit contact info in templates/index.html"
echo "   5. Change admin password in .env for production"
EOF

chmod +x setup-paneintheglass.sh

echo "✅ Complete setup script created!"
echo ""
echo "🚀 To create and run the project:"
echo "   1. Download the script above (setup-paneintheglass.sh)"
echo "   2. chmod +x setup-paneintheglass.sh"
echo "   3. ./setup-paneintheglass.sh"
echo ""
echo "The script will:"
echo "   • Create ~/Programming/paneintheglass"
echo "   • Install all dependencies with uv"
echo "   • Set up the complete website"
echo "   • Give you instructions to run it"
echo ""
echo "🌐 Website: http://localhost:5000"
echo "🔑 Admin password: glassart2024"
