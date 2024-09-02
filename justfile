
default: build serve

build:
    zola build

serve:
    zola serve

update:
    git submodule update --init --recursive