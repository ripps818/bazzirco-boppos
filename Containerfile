# syntax=docker/dockerfile:1

# Use the bazzirco-dx image as our base.
# Using a specific tag like :latest is common, but pinning to a specific
# version (e.g., :20240501) gives you more reproducible builds.
FROM ghcr.io/bazzirco/bazzirco-dx:latest

# Add some standard labels to your image for better metadata.
# You can point this to your own GitHub repository where you store this file.
LABEL org.opencontainers.image.source="https://github.com/ripps818/bazzirco-boppos"
LABEL org.opencontainers.image.description="A custom OS image with my favorite tools."

# This is the core of our customization. We run commands to modify the image.
RUN --mount=type=cache,target=/var/cache/dnf --mount=type=tmpfs,target=/run \
    # This line ensures the script exits immediately if a command fails.
    set -euxo pipefail && \
    \
    # --- Enable RPM Fusion Repositories --- \
    dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm && \
    \
    # --- Add External Repositories --- \
    # We need to add sources for packages not in the default Fedora repos.
    \
    # 1. Mullvad VPN Repository
    curl -fsSLo /etc/yum.repos.d/mullvad.repo https://repository.mullvad.net/rpm/stable/mullvad.repo && \
    \
    # 2. Cloudflare WARP Repository
    curl -fsSL --retry 3 -o /tmp/cloudflare-pubkey.gpg https://pkg.cloudflareclient.com/pubkey.gpg && \
    rpm --import /tmp/cloudflare-pubkey.gpg && \
    curl -fsSl https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo -o /etc/yum.repos.d/cloudflare-warp.repo && \
    \
    # 3. Howdy Face Unlock (from a COPR repository)
    # We dynamically determine the Fedora version to fetch the correct repo file.
    FEDORA_VERSION=$(rpm -E %fedora) && \
    curl -fsSLo "/etc/yum.repos.d/_copr_starfish-howdy-beta.repo" "https://copr.fedorainfracloud.org/coprs/starfish/howdy-beta/repo/fedora-${FEDORA_VERSION}/starfish-howdy-beta-fedora-${FEDORA_VERSION}.repo" && \
    \
    # 4. CachyOS Kernel Repository
    curl -fsSLo /etc/yum.repos.d/kernel-cachyos.repo "https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/repo/fedora-${FEDORA_VERSION}/bieszczaders-kernel-cachyos-fedora-${FEDORA_VERSION}.repo" && \
    \
    # 5. CachyOS Addons Repository
    curl -fsSLo /etc/yum.repos.d/kernel-cachyos-addons.repo "https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/repo/fedora-${FEDORA_VERSION}/bieszczaders-kernel-cachyos-addons-fedora-${FEDORA_VERSION}.repo" && \
    \
    # 6. Eza and Starship Repositories
    curl -fsSLo /etc/yum.repos.d/_copr_alternateved-eza.repo "https://copr.fedorainfracloud.org/coprs/alternateved/eza/repo/fedora-${FEDORA_VERSION}/alternateved-eza-fedora-${FEDORA_VERSION}.repo" && \
    curl -fsSLo /etc/yum.repos.d/_copr_atim-starship.repo "https://copr.fedorainfracloud.org/coprs/atim/starship/repo/fedora-${FEDORA_VERSION}/atim-starship-fedora-${FEDORA_VERSION}.repo" && \
    \
    # 7. Asus Linux Repository
    curl -fsSLo /etc/yum.repos.d/_copr_lukenukem-asus-linux.repo "https://copr.fedorainfracloud.org/coprs/lukenukem/asus-linux/repo/fedora-${FEDORA_VERSION}/lukenukem-asus-linux-fedora-${FEDORA_VERSION}.repo" && \
    \
    # --- Upgrade Key Packages --- \
    # This ensures we have the latest versions of packages that update frequently.
    # The bazzirco base image is updated weekly, but this pulls the latest 'code' at build time.
    # Add other packages here you want to keep on the bleeding edge.
    dnf upgrade -y code && \
    \
    # Force a refresh of all repository metadata before installing new packages.
    dnf makecache && \
    \
    # --- Replace Kernel --- \
    # This is an advanced customization. We are replacing the default Fedora kernel
    # with the performance-tuned CachyOS kernel. This can improve responsiveness
    # but comes with stability trade-offs. SECURE BOOT MUST BE DISABLED.
    # Mask kernel install hooks to prevent failures with custom kernels.
    # We will manually run dracut later.
    mkdir -p /etc/kernel/install.d && \
    ln -s /dev/null /etc/kernel/install.d/05-rpmostree.install && \
    ln -s /dev/null /etc/kernel/install.d/20-grub.install && \
    ln -s /dev/null /etc/kernel/install.d/50-dracut.install && \
    ln -s /dev/null /etc/kernel/install.d/90-loaderentry.install && \
    \
    dnf remove -y kernel kernel-core kernel-modules kernel-modules-extra && \
    dnf install -y kernel-cachyos kernel-cachyos-devel && \
    \
    # --- Workaround for /opt --- \
    # On bootc/ostree images, /opt is not persistent. We symlink it to /usr/lib/opt
    # so that packages that install there (like Mullvad and Cloudflare) are
    # correctly layered into the immutable image.
    rm -rf /opt && \
    mkdir -p /usr/lib/opt && \
    ln -s /usr/lib/opt /opt && \
    \
    # --- Install Packages --- \
    # We install all desired packages in a single dnf layer.
    dnf install -y \
        # VPNs
        mullvad-vpn \
        cloudflare-warp \
        tailscale \
        \
        # Power Management
        # TLP is an advanced power management tool for optimizing battery life.
        tlp \
        tlp-rdw \
        \
        # CLI Bling
        eza \
        starship \
        atuin \
        bat \
        fd-find \
        ripgrep \
        fzf \
        zoxide \
        fastfetch \
        gh && \
    \
    # --- Kernel Post-build Cleanup and Initramfs Generation --- \
    KERNEL_VERSION=$(rpm -q kernel-cachyos --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}') && \
    \
    # Clean up old kernel modules to save space
    cd /usr/lib/modules && \
    find . -maxdepth 1 -mindepth 1 -type d ! -name "$KERNEL_VERSION" -exec rm -rf {} + && \
    \
    # Clean up old kernel headers
    if [ -d "/usr/src/kernels" ]; then \
        cd /usr/src/kernels && \
        find . -maxdepth 1 -mindepth 1 -type d ! -name "$KERNEL_VERSION" -exec rm -rf {} +; \
    fi && \
    \
    # Ensure vmlinuz is in the correct location
    TARGET_KERNEL="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz" && \
    if [[ ! -f "$TARGET_KERNEL" ]]; then \
        cp -a "/boot/vmlinuz-${KERNEL_VERSION}" "$TARGET_KERNEL"; \
    fi && \
    chmod 755 "$TARGET_KERNEL" && \
    \
    # Manually generate the initramfs for the new kernel
    INITRAMFS="/usr/lib/modules/${KERNEL_VERSION}/initramfs.img" && \
    depmod -a "$KERNEL_VERSION" && \
    dracut --no-hostonly --kver "$KERNEL_VERSION" --reproducible -v --add ostree -f "$INITRAMFS" && \
    chmod 0600 "$INITRAMFS" && \
    \
    # Clean /boot directory
    rm -rf /boot/* && \
    \
    # --- Enable System Services --- \
    # Enable services that should start on boot.
    systemctl enable tlp.service && \
    \
    # --- Cleanup --- \
    # Clean up metadata and temporary files to keep the final image size smaller.
    # We exclude cache mounts from deletion to avoid "Device or resource busy" errors.
    find /var/cache -mindepth 1 -maxdepth 1 ! -name dnf ! -name libdnf5 -exec rm -rf {} + && \
    rm -rf /var/tmp/*

# The CMD instruction is inherited from the base image, so we don't need to set it.
