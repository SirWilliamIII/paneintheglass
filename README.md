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
