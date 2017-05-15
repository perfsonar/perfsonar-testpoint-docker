#
# Makefile for perfSONAR Toolkit Docker Container
#

NAME=perfsonar/testpoint-docker

GETID=$$(docker ps --format "{{.ID}}" --filter "image=$(NAME)")

default:
	@echo Nothing to do by default


# Build the container from scratch
build:
	$(GETID) | xargs -r docker rmi -f
	docker build \
		--no-cache --rm=true \
		-t "$(NAME)" \
		.


# Start the container
start:
	docker run -d -P --net=host $(NAME)


# Start a shell on the container
login:
	docker exec -it $(GETID) bash


# Stop the container
stop:
	docker kill $(GETID)


# Get rid of the images and containers
remove:
	docker ps -a -q | fgrep "$(NAME)" | xargs -r docker stop
	docker ps -a -q | fgrep "$(NAME)" | xargs -r docker rm
	docker images -a -q | fgrep "$(NAME)" | xargs -r docker rmi


clean:
	rm -rf $(TO_CLEAN)
	find . -name "*~" | xargs rm -rf
