#!/usr/bin/env bash
set -e

# Clone the repo, checkout the version and the submodule
git clone https://github.com/shigabeev/kohya_ss.git /kohya_ss
cd /kohya_ss
mv /requirements* /kohya_ss/
git checkout ${KOHYA_VERSION}
git submodule update --init --recursive

# Create and source the venv
mkdir -p /venvs
python3 -m venv --system-site-packages /venvs/kohya_ss
source /venvs/kohya_ss/bin/activate

# Install torch and xformers
pip3 install --no-cache-dir torch==${KOHYA_TORCH_VERSION} torchvision torchaudio --index-url ${INDEX_URL}
pip3 install --no-cache-dir xformers==${KOHYA_XFORMERS_VERSION} --index-url ${INDEX_URL}

# Install some additional Python modules
pip3 install bitsandbytes==0.43.0 \
    tensorboard==2.14.1 tensorflow==2.14.0 \
    wheel packaging tensorrt
pip3 install tensorflow[and-cuda]

# Install requirements and cleanup
pip3 install -r requirements.txt
pip3 cache purge
deactivate
