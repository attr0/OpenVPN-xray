# OpenVPN to V2Ray Node

Convert OpenVPN to a V2Ray node based on docker. Use [xray](https://github.com/XTLS/Xray-core) as the v2ray backend.


Similar Project to [OpenVPN-soga](https://github.com/attr0/OpenVPN-soga)


# Usage

## Environment Requirement

- Docker
- Docker Compose



Please prepare them yourself and clone this project into your disk.

```bash
git clone https://github.com/attr0/OpenVPN-xray.git openvpn-xray
cd openvpn-xray
```



## Build Image

This will generate an image including the latest soga and OpenVPN.

```bash
chmod +x ./build_container.sh
./build_container.sh
```



The image is called `OpenVPN-xray`. Use the following command to see.

```
docker image ls
```



## Configuration

**One folder means one node.**

Please copy node-example to your-node. 

```bash
cp node-example <your-node>
```



There are four configurations.

- `config.json`

    Xray Configuration. 
    
    If ssl cert is required, please also place them in this folder,  name them as `ssl.key` and `ssl.pem` respectively, and enable file mapper in the docker-compose by uncommenting the last two lines. In the configuration, use paths -- `/ssl.key` and `/ssl.pem` -- to load the cert.


- `vpn.ovpn`

    OpenVPN configuration file, please change to yours

    If password auth is required, change

    ```
    auth-user-pass
    ```
    To

    ```
    auth-user-pass /vpn.auth
    ```

    

- `vpn.auth`

    auth file for OpenVPN. If password auth is required, please change it to

    ```
    your_username
    your_password
    ```

    

- `docker-compose.yml`

    controls the name of the container, ports, and file

    - change container name to yours (must be unique)

    - change ports as you desire (must follow the v2ray configuration)

    - change the file map if you wish

        > !DO NOT CHANGE THE FILE PATH ON THE CONTAINER SIDE (RIGHT OF THE COLON)



## Start

```bash
docker-compose up -d
docker logs <your_container_name>
```

Startup the container, and print the log.



In case you need to change your configuration.

```bash
docker restart <your_container_name>
```



## Update

1. Rebuild the image

    ```bash
    ./build_container.sh
    ```

2. Recompose

    ```bash
    cd <your_node>
    docker-compose up -d
    ```


Enjoy it & Star⭐ it