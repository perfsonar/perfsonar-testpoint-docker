#
# Makefile for perfSONAR Toolkit Docker Container
#

NAME=perfsonar/testpoint-docker

default:
	@echo Nothing to do by default


build:
	docker build \
		--no-cache --rm=true \
		-t "$(NAME):$$(date +%Y%m%d%H%M%S)" \
		.


run:
	docker run -d -P --net=host \
		$(NAME)

login:
	docker exec -it ID bash


docker-clean:
	docker ps -a -q | fgrep "$(NAME)" | xargs -r docker stop
	docker ps -a -q | fgrep "$(NAME)" | xargs -r docker rm
	docker images -a -q | fgrep "$(NAME)" | xargs -r docker rmi


clean:
	rm -rf $(TO_CLEAN) *~
