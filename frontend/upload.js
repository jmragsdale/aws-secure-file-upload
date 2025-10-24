// Configuration - Update these after Terraform deployment
const CONFIG = {
    API_ENDPOINT: 'YOUR_API_GATEWAY_URL', // e.g., https://abc123.execute-api.us-east-1.amazonaws.com/prod
    API_KEY: 'YOUR_API_KEY', // From Terraform output
    MAX_FILE_SIZE: 50 * 1024 * 1024, // 50MB
    ALLOWED_TYPES: [
        'image/jpeg',
        'image/png',
        'image/gif',
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/zip'
    ]
};

// DOM Elements
const uploadArea = document.getElementById('uploadArea');
const fileInput = document.getElementById('fileInput');
const fileList = document.getElementById('fileList');

// State
let uploadQueue = [];

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    setupEventListeners();
});

function setupEventListeners() {
    // Click to upload
    uploadArea.addEventListener('click', () => fileInput.click());
    
    // File input change
    fileInput.addEventListener('change', (e) => {
        handleFiles(Array.from(e.target.files));
        fileInput.value = ''; // Reset input
    });
    
    // Drag and drop
    uploadArea.addEventListener('dragover', (e) => {
        e.preventDefault();
        uploadArea.classList.add('drag-over');
    });
    
    uploadArea.addEventListener('dragleave', () => {
        uploadArea.classList.remove('drag-over');
    });
    
    uploadArea.addEventListener('drop', (e) => {
        e.preventDefault();
        uploadArea.classList.remove('drag-over');
        handleFiles(Array.from(e.dataTransfer.files));
    });
}

function handleFiles(files) {
    files.forEach(file => {
        // Validate file
        const validation = validateFile(file);
        
        if (!validation.valid) {
            showNotification(validation.error, 'error');
            return;
        }
        
        // Add to upload queue
        const uploadItem = {
            id: generateId(),
            file: file,
            status: 'pending',
            progress: 0
        };
        
        uploadQueue.push(uploadItem);
        renderFileItem(uploadItem);
        
        // Start upload
        uploadFile(uploadItem);
    });
}

function validateFile(file) {
    // Check file size
    if (file.size > CONFIG.MAX_FILE_SIZE) {
        return {
            valid: false,
            error: `File "${file.name}" exceeds maximum size of ${CONFIG.MAX_FILE_SIZE / (1024 * 1024)}MB`
        };
    }
    
    // Check file type
    if (!CONFIG.ALLOWED_TYPES.includes(file.type)) {
        return {
            valid: false,
            error: `File type "${file.type}" is not allowed for "${file.name}"`
        };
    }
    
    return { valid: true };
}

async function uploadFile(uploadItem) {
    try {
        updateItemStatus(uploadItem.id, 'requesting');
        
        // Step 1: Get presigned URL
        const uploadUrl = await getPresignedUrl(uploadItem.file);
        
        updateItemStatus(uploadItem.id, 'uploading');
        
        // Step 2: Upload to S3
        await uploadToS3(uploadUrl, uploadItem.file, (progress) => {
            updateItemProgress(uploadItem.id, progress);
        });
        
        updateItemStatus(uploadItem.id, 'scanning');
        
        // Note: Scanning happens automatically via Lambda
        // In a production app, you might poll for status or use WebSockets
        
        setTimeout(() => {
            updateItemStatus(uploadItem.id, 'complete');
            showNotification(`File "${uploadItem.file.name}" uploaded successfully!`, 'success');
        }, 2000);
        
    } catch (error) {
        console.error('Upload error:', error);
        updateItemStatus(uploadItem.id, 'error', error.message);
        showNotification(`Failed to upload "${uploadItem.file.name}": ${error.message}`, 'error');
    }
}

async function getPresignedUrl(file) {
    const response = await fetch(`${CONFIG.API_ENDPOINT}/get-upload-url`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'x-api-key': CONFIG.API_KEY
        },
        body: JSON.stringify({
            filename: file.name,
            contentType: file.type,
            fileSize: file.size
        })
    });
    
    if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Failed to get upload URL');
    }
    
    const data = await response.json();
    return data.uploadUrl;
}

async function uploadToS3(url, file, onProgress) {
    return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        
        xhr.upload.addEventListener('progress', (e) => {
            if (e.lengthComputable) {
                const progress = (e.loaded / e.total) * 100;
                onProgress(progress);
            }
        });
        
        xhr.addEventListener('load', () => {
            if (xhr.status === 200) {
                resolve();
            } else {
                reject(new Error(`Upload failed with status ${xhr.status}`));
            }
        });
        
        xhr.addEventListener('error', () => {
            reject(new Error('Network error during upload'));
        });
        
        xhr.open('PUT', url);
        xhr.setRequestHeader('Content-Type', file.type);
        xhr.send(file);
    });
}

function renderFileItem(uploadItem) {
    const itemDiv = document.createElement('div');
    itemDiv.className = 'file-item';
    itemDiv.id = `file-${uploadItem.id}`;
    
    itemDiv.innerHTML = `
        <div class="file-info">
            <span class="file-name">${uploadItem.file.name}</span>
            <span class="file-size">${formatFileSize(uploadItem.file.size)}</span>
        </div>
        <div class="file-progress">
            <div class="progress-bar">
                <div class="progress-fill" style="width: 0%"></div>
            </div>
            <span class="file-status">Pending...</span>
        </div>
    `;
    
    fileList.appendChild(itemDiv);
}

function updateItemStatus(id, status, errorMessage = '') {
    const item = uploadQueue.find(i => i.id === id);
    if (item) item.status = status;
    
    const itemDiv = document.getElementById(`file-${id}`);
    if (!itemDiv) return;
    
    const statusSpan = itemDiv.querySelector('.file-status');
    
    const statusMessages = {
        'pending': 'Pending...',
        'requesting': 'Requesting upload URL...',
        'uploading': 'Uploading...',
        'scanning': 'Scanning for malware...',
        'complete': '✓ Complete',
        'error': `✗ Error: ${errorMessage}`
    };
    
    statusSpan.textContent = statusMessages[status] || status;
    itemDiv.className = `file-item status-${status}`;
}

function updateItemProgress(id, progress) {
    const itemDiv = document.getElementById(`file-${id}`);
    if (!itemDiv) return;
    
    const progressFill = itemDiv.querySelector('.progress-fill');
    progressFill.style.width = `${progress}%`;
    
    const statusSpan = itemDiv.querySelector('.file-status');
    statusSpan.textContent = `Uploading... ${Math.round(progress)}%`;
}

function showNotification(message, type = 'info') {
    // Create notification element
    const notification = document.createElement('div');
    notification.className = `notification notification-${type}`;
    notification.textContent = message;
    
    document.body.appendChild(notification);
    
    // Animate in
    setTimeout(() => notification.classList.add('show'), 10);
    
    // Remove after 5 seconds
    setTimeout(() => {
        notification.classList.remove('show');
        setTimeout(() => notification.remove(), 300);
    }, 5000);
}

function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
}

function generateId() {
    return Date.now().toString(36) + Math.random().toString(36).substr(2);
}
