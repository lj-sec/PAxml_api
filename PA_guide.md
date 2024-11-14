#PALO ALTO / UBUNTU WORKSTATION STEP BY STEP

UBUNTU WORKSTATION
1. Login
2. passwd - change default passwords
3. sudo apt update -y && sudo apt upgrade -y
4. sudo apt install git
5. git clone https://github.com/ravesec/eku-ccdc
6. cd eku-ccdc/scripts/linux/
7. vim xml_api.sh - Ensure that the variables are set correctly in xml_sh
8. sudo ./xml_api.sh
9. Open Firefox
10. Nav to Palo Alto IP - Login using credentials
11. Click on device -> administrators -> admin
12. Change admin password
13. 