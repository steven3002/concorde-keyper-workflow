ARG NODE_IMAGE
ARG PI_VERSION

FROM ${NODE_IMAGE}
ARG PI_VERSION

RUN apk add --no-cache curl socat

RUN npm install -g @earendil-works/pi-coding-agent@${PI_VERSION}

WORKDIR /workspace
ENV PI_CODING_AGENT_DIR=/home/agent/.pi/agent
