FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime
WORKDIR /lesson
COPY requirements.txt /lesson/requirements.txt
RUN pip install --no-cache-dir -r /lesson/requirements.txt
COPY prepare.py train_text.py train_image.py check_bundle.py run_all.sh /lesson/
RUN chmod +x /lesson/run_all.sh
ENV PYTHONUNBUFFERED=1
