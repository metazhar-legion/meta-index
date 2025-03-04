#!/bin/bash

# Web3 Index Fund Frontend Deployment Script

echo "Starting deployment of Web3 Index Fund Frontend..."

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is not installed. Please install Node.js before proceeding."
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "Error: npm is not installed. Please install npm before proceeding."
    exit 1
fi

# Install dependencies
echo "Installing dependencies..."
npm install

# Build the production version
echo "Building production version..."
npm run build

# Check if the build was successful
if [ ! -d "build" ]; then
    echo "Error: Build failed. Please check the logs above for more information."
    exit 1
fi

echo "Build successful!"

# Deploy options
echo ""
echo "Deployment options:"
echo "1. Deploy to local server (for testing)"
echo "2. Deploy to AWS S3 (requires AWS CLI)"
echo "3. Deploy to GitHub Pages (requires gh-pages package)"
echo "4. Create a deployment archive (for manual deployment)"
echo ""
read -p "Select deployment option (1-4): " deployment_option

case $deployment_option in
    1)
        # Deploy to local server
        echo "Starting local server..."
        npx serve -s build
        ;;
    2)
        # Deploy to AWS S3
        read -p "Enter S3 bucket name: " s3_bucket
        
        # Check if AWS CLI is installed
        if ! command -v aws &> /dev/null; then
            echo "Error: AWS CLI is not installed. Please install it before proceeding."
            exit 1
        fi
        
        echo "Deploying to AWS S3 bucket: $s3_bucket..."
        aws s3 sync build/ s3://$s3_bucket --delete
        
        # Check if CloudFront distribution ID is provided for cache invalidation
        read -p "Enter CloudFront distribution ID (leave empty to skip): " cloudfront_id
        if [ ! -z "$cloudfront_id" ]; then
            echo "Creating CloudFront invalidation..."
            aws cloudfront create-invalidation --distribution-id $cloudfront_id --paths "/*"
        fi
        
        echo "Deployment to AWS S3 complete!"
        echo "Your site should be available at: http://$s3_bucket.s3-website-$(aws configure get region).amazonaws.com"
        ;;
    3)
        # Deploy to GitHub Pages
        echo "Installing gh-pages package..."
        npm install --save-dev gh-pages
        
        # Add deploy script to package.json if it doesn't exist
        if ! grep -q '"deploy": "gh-pages -d build"' package.json; then
            # This is a simple way to add the script, but it's not perfect for all package.json structures
            sed -i '' 's/"scripts": {/"scripts": {\n    "deploy": "gh-pages -d build",/g' package.json
        fi
        
        echo "Deploying to GitHub Pages..."
        npm run deploy
        
        echo "Deployment to GitHub Pages complete!"
        echo "Your site should be available at: https://[username].github.io/[repository-name]"
        echo "Note: It may take a few minutes for the changes to propagate."
        ;;
    4)
        # Create deployment archive
        echo "Creating deployment archive..."
        zip_file="web3-index-fund-frontend-$(date +%Y%m%d%H%M%S).zip"
        
        # Check if zip command is available
        if command -v zip &> /dev/null; then
            cd build && zip -r ../$zip_file . && cd ..
            echo "Deployment archive created: $zip_file"
            echo "You can manually deploy this archive to your hosting provider."
        else
            echo "Error: 'zip' command not found. Creating a tar.gz archive instead."
            tar_file="web3-index-fund-frontend-$(date +%Y%m%d%H%M%S).tar.gz"
            cd build && tar -czvf ../$tar_file . && cd ..
            echo "Deployment archive created: $tar_file"
            echo "You can manually deploy this archive to your hosting provider."
        fi
        ;;
    *)
        echo "Invalid option selected. Exiting."
        exit 1
        ;;
esac

echo ""
echo "Deployment process completed!"
