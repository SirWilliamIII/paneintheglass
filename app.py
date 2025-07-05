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

# Database configuration - Use simple current directory path
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///portfolio.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# File upload configuration
app.config['UPLOAD_FOLDER'] = 'static/uploads'
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}

# Admin password
ADMIN_PASSWORD_HASH = generate_password_hash('glassart2024')

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
            'file_size': self.file_size,
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
    app.run(debug=True, host='0.0.0.0', port=5555)
