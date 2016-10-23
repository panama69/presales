This Dockerfile is based on the one provided by Jenkins on their 2.19.1 release.

The VOLUME tag has been commented out so there is no external data (all stored within the Docker image)

Key things done after the Docker build -t <imageName> .  In other words, you need to manually perform these steps
- started the image and ran through the "install common plugins" though this isnt required as the Dockerfile includes the ones needed for presales.
  - docker run -d -p 8080:8080 -p 50000:50000 --name <containerName> <imageName>
- turned off security so no username/passwords required
- commit the container to create new image containing the changes for distribution
  - docker commit CONTAINER [REPOSITORY[:TAG]]
- push the new image to a Docker repo
