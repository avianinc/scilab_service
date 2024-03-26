# Use an official Python runtime as a parent image
FROM python:3.8-slim-buster

# Set environment variables
ENV FLASK_APP_DIR=/home/flask_scilab \
    EFS_BASE_DIR=/mnt/cdefs/results

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    scilab \
    && rm -rf /var/lib/apt/lists/*

# Install Flask
RUN pip install Flask

# Set up the application directory
WORKDIR $FLASK_APP_DIR

# Copy the Flask application into the container
COPY app.py $FLASK_APP_DIR/

# Expose the port the app runs on
EXPOSE 5000

# Define environment variable
ENV EFS_BASE_DIR=$EFS_BASE_DIR

# Run the Flask application
CMD ["flask", "run", "--host=0.0.0.0"]
