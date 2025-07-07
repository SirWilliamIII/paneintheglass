import os
import uuid
import io
from datetime import datetime
from werkzeug.utils import secure_filename
from werkzeug.security import check_password_hash, generate_password_hash
from flask import Flask, request, jsonify, render_template, send_from_directory, session, redirect
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from PIL import Image
import secrets
from dotenv import load_dotenv
import boto3
from botocore.exceptions import ClientError

# Load environment variables
load_dotenv()

# Initialize Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', secrets.token_hex(16))

# Database configuration
database_url = os.environ.get('DATABASE_URL')
if database_url:
    # Heroku provides DATABASE_URL, but we need to handle the postgres:// prefix
    if database_url.startswith('postgres://'):
        database_url = database_url.replace('postgres://', 'postgresql://', 1)
    app.config['SQLALCHEMY_DATABASE_URI'] = database_url
else:
    # Local development fallback
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///portfolio.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# File upload configuration
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp'}

# AWS S3 configuration
AWS_ACCESS_KEY_ID = os.environ.get('AWS_ACCESS_KEY_ID')
AWS_SECRET_ACCESS_KEY = os.environ.get('AWS_SECRET_ACCESS_KEY')
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
S3_BUCKET = os.environ.get('S3_BUCKET')

# Initialize S3 client
s3_client = None
if AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY and S3_BUCKET:
    s3_client = boto3.client(
        's3',
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
        region_name=AWS_REGION
    )

# Admin password
admin_password = os.environ.get('ADMIN_PASSWORD', 'kimsuan')
ADMIN_PASSWORD_HASH = generate_password_hash(admin_password)

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
            'image_url': f'https://{S3_BUCKET}.s3.{AWS_REGION}.amazonaws.com/{self.filename}' if S3_BUCKET else f'/uploads/{self.filename}',
            'thumbnail_url': f'https://{S3_BUCKET}.s3.{AWS_REGION}.amazonaws.com/thumbnails/{self.filename}' if S3_BUCKET else f'/uploads/thumbnails/{self.filename}'
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

def upload_to_s3(file_obj, filename, content_type='image/jpeg'):
    """Upload file to S3 bucket"""
    if not s3_client:
        return False
    
    try:
        s3_client.upload_fileobj(
            file_obj,
            S3_BUCKET,
            filename,
            ExtraArgs={'ContentType': content_type}
        )
        return True
    except ClientError as e:
        print(f"Error uploading to S3: {e}")
        return False

def delete_from_s3(filename):
    """Delete file from S3 bucket"""
    if not s3_client:
        return False
    
    try:
        s3_client.delete_object(Bucket=S3_BUCKET, Key=filename)
        return True
    except ClientError as e:
        print(f"Error deleting from S3: {e}")
        return False

def create_thumbnail_s3(image_data, filename, size=(400, 400)):
    """Create thumbnail and upload to S3"""
    try:
        with Image.open(io.BytesIO(image_data)) as img:
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
            
            # Save thumbnail to bytes
            thumb_buffer = io.BytesIO()
            thumb.save(thumb_buffer, 'JPEG', quality=85)
            thumb_buffer.seek(0)
            
            # Upload thumbnail to S3
            thumbnail_filename = f"thumbnails/{filename}"
            return upload_to_s3(thumb_buffer, thumbnail_filename, 'image/jpeg')
    except Exception as e:
        print(f"Error creating thumbnail: {e}")
        return False

def ensure_upload_directories():
    """Create local directories for fallback (development mode)"""
    if not S3_BUCKET:
        upload_dir = 'static/uploads'
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
        
        # Read file data
        file_data = file.read()
        file_size = len(file_data)
        
        try:
            with Image.open(io.BytesIO(file_data)) as img:
                width, height = img.size
        except Exception as e:
            return jsonify({'error': f'Invalid image file: {str(e)}'}), 400
        
        # Upload to S3 or save locally
        if S3_BUCKET and s3_client:
            # Upload original image to S3
            file_obj = io.BytesIO(file_data)
            content_type = f"image/{unique_filename.split('.')[-1].lower()}"
            if not upload_to_s3(file_obj, unique_filename, content_type):
                return jsonify({'error': 'Failed to upload image to S3'}), 500
            
            # Create and upload thumbnail
            if not create_thumbnail_s3(file_data, unique_filename):
                return jsonify({'error': 'Failed to create thumbnail'}), 500
        else:
            # Fallback to local storage
            image_path = os.path.join('static/uploads', unique_filename)
            with open(image_path, 'wb') as f:
                f.write(file_data)
            
            thumbnail_path = os.path.join('static/uploads', 'thumbnails', unique_filename)
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
            # Clean up uploaded files on error
            if S3_BUCKET and s3_client:
                delete_from_s3(unique_filename)
                delete_from_s3(f"thumbnails/{unique_filename}")
            else:
                image_path = os.path.join('static/uploads', unique_filename)
                thumbnail_path = os.path.join('static/uploads', 'thumbnails', unique_filename)
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
    
    # Delete from S3 or local storage
    if S3_BUCKET and s3_client:
        delete_from_s3(image.filename)
        delete_from_s3(f"thumbnails/{image.filename}")
    else:
        # Fallback to local file deletion
        image_path = os.path.join('static/uploads', image.filename)
        thumbnail_path = os.path.join('static/uploads', 'thumbnails', image.filename)
        
        if os.path.exists(image_path):
            os.remove(image_path)
        if os.path.exists(thumbnail_path):
            os.remove(thumbnail_path)
    
    db.session.delete(image)
    db.session.commit()
    
    return jsonify({'success': True, 'message': 'Image deleted successfully'})

@app.route('/uploads/<filename>')
def uploaded_file(filename):
    if S3_BUCKET:
        # Redirect to S3 URL
        s3_url = f"https://{S3_BUCKET}.s3.{AWS_REGION}.amazonaws.com/{filename}"
        return redirect(s3_url)
    else:
        # Fallback to local file serving
        return send_from_directory('static/uploads', filename)

@app.route('/uploads/thumbnails/<filename>')
def uploaded_thumbnail(filename):
    if S3_BUCKET:
        # Redirect to S3 URL
        s3_url = f"https://{S3_BUCKET}.s3.{AWS_REGION}.amazonaws.com/thumbnails/{filename}"
        return redirect(s3_url)
    else:
        # Fallback to local file serving
        thumbnail_dir = os.path.join('static/uploads', 'thumbnails')
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
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('DEBUG', 'False').lower() == 'true'
    app.run(debug=debug, host='0.0.0.0', port=port)
