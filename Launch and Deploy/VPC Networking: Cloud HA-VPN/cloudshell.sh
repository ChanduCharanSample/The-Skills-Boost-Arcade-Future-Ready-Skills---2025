#!/bin/bash
set -euo pipefail

# ===== Prompt & detect variables =====
read -p "Enter first zone (for REGION1, e.g. us-east1-b): " ZONE1
read -p "Enter second zone (for REGION2, e.g. asia-east1-b): " ZONE2

REGION1=$(echo "${ZONE1}" | awk -F'-' '{print $1"-"$2}')
REGION2=$(echo "${ZONE2}" | awk -F'-' '{print $1"-"$2}')
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "UNKNOWN_PROJECT")

# Shared secret for VPN tunnels
SHARED_SECRET="myvpnsecret123"

echo
echo "Project ID : ${PROJECT_ID}"
echo "ZONE1       : ${ZONE1}   (REGION1=${REGION1})"
echo "ZONE2       : ${ZONE2}   (REGION2=${REGION2})"
echo "Shared Key  : ${SHARED_SECRET}"
echo

read -p "Proceed with these settings and create lab resources? (y/n): " PROCEED
if [[ "${PROCEED}" != "y" ]]; then
  echo "Aborted by user."
  exit 1
fi

# Give friendly timestamps
TS() { echo "==> $(date +'%Y-%m-%d %H:%M:%S') $*"; }

# ===== Task 1: Cloud VPC setup =====
TS "Creating VPC networks (vpc-demo and on-prem)..."
gcloud compute networks create vpc-demo --subnet-mode custom
gcloud compute networks create on-prem  --subnet-mode custom

TS "Creating subnets..."
gcloud beta compute networks subnets create vpc-demo-subnet1 \
  --network vpc-demo --range 10.1.1.0/24 --region "${REGION1}"

gcloud beta compute networks subnets create vpc-demo-subnet2 \
  --network vpc-demo --range 10.2.1.0/24 --region "${REGION2}"

gcloud beta compute networks subnets create on-prem-subnet1 \
  --network on-prem --range 192.168.1.0/24 --region "${REGION1}"

# ===== Task 1: Firewall rules (internal + SSH/ICMP) =====
TS "Creating firewall rules..."
gcloud compute firewall-rules create vpc-demo-allow-internal \
  --network vpc-demo \
  --allow tcp:0-65535,udp:0-65535,icmp \
  --source-ranges 10.0.0.0/8 || true

gcloud compute firewall-rules create vpc-demo-allow-ssh-icmp \
  --network vpc-demo \
  --allow tcp:22,icmp || true

gcloud compute firewall-rules create on-prem-allow-internal \
  --network on-prem \
  --allow tcp:0-65535,udp:0-65535,icmp \
  --source-ranges 192.168.0.0/16 || true

gcloud compute firewall-rules create on-prem-allow-ssh-icmp \
  --network on-prem \
  --allow tcp:22,icmp || true

# ===== Task 2: Create test VMs =====
TS "Creating test VM instances..."
# vpc-demo-instance1 in REGION1 zone (subnet vpc-demo-subnet1)
gcloud compute instances create vpc-demo-instance1 \
  --zone "${ZONE1}" \
  --subnet vpc-demo-subnet1 \
  --machine-type e2-medium \
  --image-family debian-12 --image-project debian-cloud

# vpc-demo-instance2 in REGION2 zone (subnet vpc-demo-subnet2)
gcloud compute instances create vpc-demo-instance2 \
  --zone "${ZONE2}" \
  --subnet vpc-demo-subnet2 \
  --machine-type e2-medium \
  --image-family debian-12 --image-project debian-cloud

# on-prem-instance1 in REGION1 zone (subnet on-prem-subnet1)
gcloud compute instances create on-prem-instance1 \
  --zone "${REGION1}-b" \
  --subnet on-prem-subnet1 \
  --machine-type e2-medium \
  --image-family debian-12 --image-project debian-cloud

# If the user provided a different specific zone for REGION1 (ZONE1),
# ensure on-prem-instance1 uses ZONE1 if desired. But the lab expects on-prem-instance1 in REGION1 and often us-east1-b.
# To strictly follow user zones we created earlier, create on-prem-instance1 in ZONE1 instead:
# (If you prefer always use REGION1-b, comment out above and uncomment below)
# gcloud compute instances create on-prem-instance1 \
#   --zone "${ZONE1}" \
#   --subnet on-prem-subnet1 \
#   --machine-type e2-medium \
#   --image-family debian-12 --image-project debian-cloud

# ===== Task 3: HA-VPN setup =====
TS "Creating Cloud HA-VPN gateways (beta)..."
gcloud beta compute vpn-gateways create vpc-demo-vpn-gw1 --network vpc-demo --region "${REGION1}"
gcloud beta compute vpn-gateways create on-prem-vpn-gw1 --network on-prem --region "${REGION1}"

TS "Describe gateway IPs (vpnInterfaces) - will be used for verification"
echo "vpc-demo vpn-gateway interfaces:"
gcloud beta compute vpn-gateways describe vpc-demo-vpn-gw1 --region "${REGION1}" --format="yaml(vpnInterfaces)"
echo
echo "on-prem vpn-gateway interfaces:"
gcloud beta compute vpn-gateways describe on-prem-vpn-gw1 --region "${REGION1}" --format="yaml(vpnInterfaces)"
echo

TS "Creating Cloud Routers..."
gcloud compute routers create vpc-demo-router1 \
  --region "${REGION1}" --network vpc-demo --asn 65001

gcloud compute routers create on-prem-router1 \
  --region "${REGION1}" --network on-prem --asn 65002

# ===== Create VPN tunnels (HA): two tunnels per gateway =====
TS "Creating VPN tunnels between vpc-demo and on-prem (HA - two tunnels each)..."

# vpc-demo -> on-prem tunnels
gcloud beta compute vpn-tunnels create vpc-demo-tunnel0 \
  --peer-gcp-gateway on-prem-vpn-gw1 \
  --region "${REGION1}" \
  --ike-version 2 \
  --shared-secret "${SHARED_SECRET}" \
  --router vpc-demo-router1 \
  --vpn-gateway vpc-demo-vpn-gw1 \
  --interface 0

gcloud beta compute vpn-tunnels create vpc-demo-tunnel1 \
  --peer-gcp-gateway on-prem-vpn-gw1 \
  --region "${REGION1}" \
  --ike-version 2 \
  --shared-secret "${SHARED_SECRET}" \
  --router vpc-demo-router1 \
  --vpn-gateway vpc-demo-vpn-gw1 \
  --interface 1

# on-prem -> vpc-demo tunnels
gcloud beta compute vpn-tunnels create on-prem-tunnel0 \
  --peer-gcp-gateway vpc-demo-vpn-gw1 \
  --region "${REGION1}" \
  --ike-version 2 \
  --shared-secret "${SHARED_SECRET}" \
  --router on-prem-router1 \
  --vpn-gateway on-prem-vpn-gw1 \
  --interface 0

gcloud beta compute vpn-tunnels create on-prem-tunnel1 \
  --peer-gcp-gateway vpc-demo-vpn-gw1 \
  --region "${REGION1}" \
  --ike-version 2 \
  --shared-secret "${SHARED_SECRET}" \
  --router on-prem-router1 \
  --vpn-gateway on-prem-vpn-gw1 \
  --interface 1

TS "Created tunnels. Listing vpn-tunnels:"
gcloud beta compute vpn-tunnels list --regions "${REGION1}"

# ===== BGP: add interfaces to routers referencing vpn-tunnels, then add bgp peers =====
TS "Adding router interfaces and BGP peers..."

# Router interfaces for vpc-demo-router1
gcloud compute routers add-interface vpc-demo-router1 \
  --interface-name if-tunnel0-to-on-prem \
  --ip-address 169.254.0.1 \
  --mask-length 30 \
  --vpn-tunnel vpc-demo-tunnel0 \
  --region "${REGION1}"

gcloud compute routers add-bgp-peer vpc-demo-router1 \
  --peer-name bgp-on-prem-tunnel0 \
  --interface if-tunnel0-to-on-prem \
  --peer-ip-address 169.254.0.2 \
  --peer-asn 65002 \
  --region "${REGION1}"

gcloud compute routers add-interface vpc-demo-router1 \
  --interface-name if-tunnel1-to-on-prem \
  --ip-address 169.254.1.1 \
  --mask-length 30 \
  --vpn-tunnel vpc-demo-tunnel1 \
  --region "${REGION1}"

gcloud compute routers add-bgp-peer vpc-demo-router1 \
  --peer-name bgp-on-prem-tunnel1 \
  --interface if-tunnel1-to-on-prem \
  --peer-ip-address 169.254.1.2 \
  --peer-asn 65002 \
  --region "${REGION1}"

# Router interfaces for on-prem-router1
gcloud compute routers add-interface on-prem-router1 \
  --interface-name if-tunnel0-to-vpc-demo \
  --ip-address 169.254.0.2 \
  --mask-length 30 \
  --vpn-tunnel on-prem-tunnel0 \
  --region "${REGION1}"

gcloud compute routers add-bgp-peer on-prem-router1 \
  --peer-name bgp-vpc-demo-tunnel0 \
  --interface if-tunnel0-to-vpc-demo \
  --peer-ip-address 169.254.0.1 \
  --peer-asn 65001 \
  --region "${REGION1}"

gcloud compute routers add-interface on-prem-router1 \
  --interface-name if-tunnel1-to-vpc-demo \
  --ip-address 169.254.1.2 \
  --mask-length 30 \
  --vpn-tunnel on-prem-tunnel1 \
  --region "${REGION1}"

gcloud compute routers add-bgp-peer on-prem-router1 \
  --peer-name bgp-vpc-demo-tunnel1 \
  --interface if-tunnel1-to-vpc-demo \
  --peer-ip-address 169.254.1.1 \
  --peer-asn 65001 \
  --region "${REGION1}"

TS "Router config added. Allow a short wait for BGP sessions..."
sleep 15

TS "Show router status (vpc-demo-router1):"
gcloud compute routers get-status vpc-demo-router1 --region "${REGION1}" || true

TS "Show router status (on-prem-router1):"
gcloud compute routers get-status on-prem-router1 --region "${REGION1}" || true

# ===== Global routing config for vpc-demo so router can see other region routes =====
TS "Updating vpc-demo to GLOBAL routing to allow cross-region reachability..."
gcloud compute networks update vpc-demo --bgp-routing-mode GLOBAL

TS "vpc-demo network description (routingConfig):"
gcloud compute networks describe vpc-demo --format="yaml(routingConfig,subnetworks)"

# ===== Verify private connectivity over VPN (ping tests) =====
TS "Running ping tests from on-prem-instance1 to vpc-demo-instance1 and vpc-demo-instance2..."

# Get internal IPs
VPC1_IP=$(gcloud compute instances describe vpc-demo-instance1 --zone "${ZONE1}" --format='get(networkInterfaces[0].networkIP)')
VPC2_IP=$(gcloud compute instances describe vpc-demo-instance2 --zone "${ZONE2}" --format='get(networkInterfaces[0].networkIP)')
ONPREM_ZONE=$(gcloud compute instances describe on-prem-instance1 --format='get(zone)' | awk -F/ '{print $NF}')
ONPREM_IP=$(gcloud compute instances describe on-prem-instance1 --zone "${ONPREM_ZONE}" --format='get(networkInterfaces[0].networkIP)')

echo "on-prem-instance1 internal IP: ${ONPREM_IP}"
echo "vpc-demo-instance1 internal IP: ${VPC1_IP}"
echo "vpc-demo-instance2 internal IP: ${VPC2_IP}"
echo

# Ping vpc-demo-instance1 from on-prem-instance1
TS "Ping ${VPC1_IP} from on-prem-instance1 (4 packets)..."
gcloud compute ssh on-prem-instance1 --zone "${ONPREM_ZONE}" \
  --command "ping -c 4 ${VPC1_IP}" --ssh-flag="-o StrictHostKeyChecking=no" || echo "Ping to ${VPC1_IP} failed (check firewall/BGP)."

# Ping vpc-demo-instance2 from on-prem-instance1
TS "Ping ${VPC2_IP} from on-prem-instance1 (4 packets)..."
gcloud compute ssh on-prem-instance1 --zone "${ONPREM_ZONE}" \
  --command "ping -c 4 ${VPC2_IP}" --ssh-flag="-o StrictHostKeyChecking=no" || echo "Ping to ${VPC2_IP} failed (check BG P/global routing)."

TS "If pings succeeded, HA-VPN connectivity is working. If not, inspect router/tunnel status and firewall rules."

# ===== Cleanup prompt =====
echo
read -p "Do you want to delete ALL created resources now? (y/n): " CLEANUP
if [[ "${CLEANUP}" == "y" ]]; then
  TS "Deleting VPN tunnels..."
  gcloud beta compute vpn-tunnels delete vpc-demo-tunnel0 vpc-demo-tunnel1 \
    on-prem-tunnel0 on-prem-tunnel1 --region "${REGION1}" --quiet || true

  TS "Removing BGP peers & routers..."
  gcloud compute routers remove-bgp-peer vpc-demo-router1 --peer-name bgp-on-prem-tunnel0 --region "${REGION1}" --quiet || true
  gcloud compute routers remove-bgp-peer vpc-demo-router1 --peer-name bgp-on-prem-tunnel1 --region "${REGION1}" --quiet || true
  gcloud compute routers remove-bgp-peer on-prem-router1 --peer-name bgp-vpc-demo-tunnel0 --region "${REGION1}" --quiet || true
  gcloud compute routers remove-bgp-peer on-prem-router1 --peer-name bgp-vpc-demo-tunnel1 --region "${REGION1}" --quiet || true

  TS "Deleting routers..."
  gcloud compute routers delete vpc-demo-router1 on-prem-router1 --region "${REGION1}" --quiet || true

  TS "Deleting VPN gateways..."
  gcloud beta compute vpn-gateways delete vpc-demo-vpn-gw1 on-prem-vpn-gw1 --region "${REGION1}" --quiet || true

  TS "Deleting VMs..."
  gcloud compute instances delete vpc-demo-instance1 --zone "${ZONE1}" --quiet || true
  gcloud compute instances delete vpc-demo-instance2 --zone "${ZONE2}" --quiet || true
  gcloud compute instances delete on-prem-instance1 --zone "${ONPREM_ZONE}" --quiet || true

  TS "Deleting firewall rules..."
  gcloud compute firewall-rules delete vpc-demo-allow-internal vpc-demo-allow-ssh-icmp on-prem-allow-internal on-prem-allow-ssh-icmp --quiet || true

  TS "Deleting subnets..."
  gcloud beta compute networks subnets delete vpc-demo-subnet1 --region "${REGION1}" --quiet || true
  gcloud beta compute networks subnets delete vpc-demo-subnet2 --region "${REGION2}" --quiet || true
  gcloud beta compute networks subnets delete on-prem-subnet1 --region "${REGION1}" --quiet || true

  TS "Deleting networks..."
  gcloud compute networks delete vpc-demo on-prem --quiet || true

  TS "Cleanup finished."
else
  TS "Skipping cleanup. Resources remain in project ${PROJECT_ID}."
fi

TS "Script finished."
