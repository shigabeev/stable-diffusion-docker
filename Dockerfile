
# Stage 1: Base Image
ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS base

RUN mkdir -p /sd-models

# Add SDXL models and VAE
# These need to already have been downloaded:
#   wget https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
#   wget https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0/resolve/main/sd_xl_refiner_1.0.safetensors
#   wget https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors
# COPY sd_xl_base_1.0.safetensors /sd-models/sd_xl_base_1.0.safetensors
# COPY sd_xl_refiner_1.0.safetensors /sd-models/sd_xl_refiner_1.0.safetensors
# COPY sdxl_vae.safetensors /sd-models/sdxl_vae.safetensors

WORKDIR /

# Stage 2: A1111 Installation
FROM base AS a1111-install
ARG WEBUI_VERSION
ARG TORCH_VERSION
ARG XFORMERS_VERSION
ARG INDEX_URL
ARG CONTROLNET_COMMIT
ARG CIVITAI_BROWSER_PLUS_VERSION
ARG DREAMBOOTH_COMMIT
COPY --chmod=755 build/install_a1111.sh ./
RUN /install_a1111.sh && rm /install_a1111.sh

# Cache the Stable Diffusion Models
# SDXL models result in OOM kills with 8GB system memory, need 30GB+ to cache these
WORKDIR /stable-diffusion-webui
COPY a1111/cache-sd-model.py ./

# Cache Base Model
RUN source /venv/bin/activate && \
    python3 cache-sd-model.py --skip-torch-cuda-test --use-cpu=all --xformers --ckpt /sd-models/sd_xl_base_1.0.safetensors && \
    deactivate

# Cache Refiner Model
RUN source /venv/bin/activate && \
    python3 cache-sd-model.py --skip-torch-cuda-test --use-cpu=all --xformers --ckpt /sd-models/sd_xl_refiner_1.0.safetensors && \
    deactivate

# RUN cd /stable-diffusion-webui && python cache.py --use-cpu=all --ckpt /model.safetensors

# Copy Stable Diffusion Web UI config files
COPY a1111/relauncher.py a1111/webui-user.sh a1111/config.json a1111/ui-config.json /stable-diffusion-webui/

# ADD SDXL styles.csv
ADD https://raw.githubusercontent.com/Douleb/SDXL-750-Styles-GPT4-/main/styles.csv /stable-diffusion-webui/styles.csv

# Stage 3: InvokeAI Installation
FROM a1111-install AS invokeai-install
ARG INVOKEAI_VERSION
WORKDIR /
COPY --chmod=755 build/install_invokeai.sh ./
RUN /install_invokeai.sh && rm /install_invokeai.sh

# Copy InvokeAI config file
COPY invokeai/invokeai.yaml /InvokeAI/

# Stage 4: Kohya_ss Installation
FROM invokeai-install AS kohya-install
ARG KOHYA_VERSION
ARG KOHYA_TORCH_VERSION
ARG KOHYA_XFORMERS_VERSION
WORKDIR /
COPY kohya_ss/requirements* ./
COPY --chmod=755 build/install_kohya.sh ./
RUN /install_kohya.sh && rm /install_kohya.sh

# Copy the accelerate configuration
COPY kohya_ss/accelerate.yaml ./

# Stage 5: ComfyUI Installation
FROM kohya-install AS comfyui-install
ARG COMFYUI_COMMIT
WORKDIR /
COPY --chmod=755 build/install_comfyui.sh ./
RUN /install_comfyui.sh && rm /install_comfyui.sh

# Copy ComfyUI Extra Model Paths (to share models with A1111)
COPY comfyui/extra_model_paths.yaml /ComfyUI/

# Stage 6: Tensorboard Installation
FROM comfyui-install AS tensorboard-install
WORKDIR /
COPY --chmod=755 build/install_tensorboard.sh ./
RUN /install_tensorboard.sh && rm /install_tensorboard.sh

# Stage 7: Application Manager Installation
FROM tensorboard-install AS appmanager-install
ARG APP_MANAGER_VERSION
WORKDIR /
COPY --chmod=755 build/install_app_manager.sh ./
RUN /install_app_manager.sh && rm /install_app_manager.sh
COPY app-manager/config.json /app-manager/public/config.json

# Stage 8: CivitAI Model Downloader Installation
FROM appmanager-install AS civitai-dl-install
ARG CIVITAI_DOWNLOADER_VERSION
WORKDIR /
COPY --chmod=755 build/install_civitai_model_downloader.sh ./
RUN /install_civitai_model_downloader.sh && rm /install_civitai_model_downloader.sh

# Stage 9: Finalise Image
FROM civitai-dl-install AS final

# Copy benchmark script
COPY scripts/benchmark.sh /workspace/

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Create necessary directories
RUN mkdir -p /workspace/datasets /workspace/ckpt

# Link ckpt folder to stable-diffusion-webui models
RUN mkdir -p /workspace/stable-diffusion-webui/models/Stable-diffusion && \
    ln -s /workspace/ckpt /workspace/stable-diffusion-webui/models/Stable-diffusion/ckpt

# Remove existing SSH host keys
RUN rm -f /etc/ssh/ssh_host_*

# NGINX Proxy
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# Set template version
ARG RELEASE
ENV TEMPLATE_VERSION=${RELEASE}

# Set the main venv path
ARG VENV_PATH
ENV VENV_PATH=${VENV_PATH}

# Copy the scripts
WORKDIR /
COPY --chmod=755 scripts/* ./

# Start the container
SHELL ["/bin/bash", "--login", "-c"]
CMD [ "/start.sh" ]
