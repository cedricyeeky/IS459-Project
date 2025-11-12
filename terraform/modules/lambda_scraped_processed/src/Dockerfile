# Use AWS Lambda Python 3.11 base image
FROM public.ecr.aws/lambda/python:3.11

# Install pandas and pyarrow
RUN pip install --no-cache-dir \
    pandas==2.0.3 \
    pyarrow==12.0.1 \
    numpy==1.24.3

# Copy function code
COPY process_scraped_data.py ${LAMBDA_TASK_ROOT}/

# Set the CMD to your handler
CMD [ "process_scraped_data.lambda_handler" ]
