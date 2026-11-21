# status

`status.sh` writes two files into the site folder every minute: `status/index.html` for people and `status.json` for programs.

## Fields

Every device reports uptime, device model, load, free disk space and CPU temperature (when the device exposes it).

- On a phone with Termux:API installed, the page adds battery percentage, charging state and battery temperature. Without Termux:API, the page leaves these fields out.
- On a Raspberry Pi, the page can add readings from a Victron solar charger. This stays off until you set `victron=true` in `solar.conf`. Set `victron_device` if your cable is not `/dev/ttyUSB0`. The script only reads from the device and never writes to it.

## Who can see the page

The installer reads `status_public` from `solar.conf`. The default is `false`: Caddy answers requests for `/status` and `/status.json` with 403 unless the request comes from a private address (192.168.x.x, 10.x.x.x, 172.16-31.x.x or localhost). Set `status_public=true` to serve the page to everyone.

If you publish the site through a tunnel such as cloudflared, Caddy sees the tunnel's local address, which counts as private. In that case the page stays visible on the internet even with `status_public=false`. Set up the tunnel to skip `/status`, or accept that the page is public.
