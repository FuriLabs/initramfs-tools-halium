#!/bin/sh

USB_FUNCTIONS=rndis
ANDROID_USB=/sys/class/android_usb/android0
GADGET_DIR=/config/usb_gadget
LOCAL_IP=192.168.2.15

write() {
	echo -n "$2" >"$1"
}

# This sets up the USB with whatever USB_FUNCTIONS are set to via configfs
usb_setup_configfs() {
    G_USB_ISERIAL=$GADGET_DIR/g1/strings/0x409/serialnumber

    mkdir $GADGET_DIR/g1
    write $GADGET_DIR/g1/idVendor                   "0x18D1"
    write $GADGET_DIR/g1/idProduct                  "0xD001"
    mkdir $GADGET_DIR/g1/strings/0x409
    write $GADGET_DIR/g1/strings/0x409/serialnumber "furios-recovery"
    write $GADGET_DIR/g1/strings/0x409/manufacturer "FuriOS recovery"
    write $GADGET_DIR/g1/strings/0x409/product      "FuriOS recovery"

    if echo $USB_FUNCTIONS | grep -q "rndis"; then
        mkdir $GADGET_DIR/g1/functions/rndis.usb0
        mkdir $GADGET_DIR/g1/functions/rndis_bam.rndis
    fi
    echo $USB_FUNCTIONS | grep -q "mass_storage" && mkdir $GADGET_DIR/g1/functions/storage.0

    mkdir $GADGET_DIR/g1/configs/c.1
    mkdir $GADGET_DIR/g1/configs/c.1/strings/0x409
    write $GADGET_DIR/g1/configs/c.1/strings/0x409/configuration "$USB_FUNCTIONS"

    if echo $USB_FUNCTIONS | grep -q "rndis"; then
        ln -s $GADGET_DIR/g1/functions/rndis.usb0 $GADGET_DIR/g1/configs/c.1
        ln -s $GADGET_DIR/g1/functions/rndis_bam.rndis $GADGET_DIR/g1/configs/c.1
    fi
    echo $USB_FUNCTIONS | grep -q "mass_storage" && ln -s $GADGET_DIR/g1/functions/storage.0 $GADGET_DIR/g1/configs/c.1

    [ -f /sys/class/udc/"$(ls /sys/class/udc | grep -v dummy | head -1)"/device/../mode ] && write /sys/class/udc/"$(ls /sys/class/udc | grep -v dummy | head -1)"/device/../mode peripheral
    echo "$(ls /sys/class/udc | grep -v dummy | head -1)" > $GADGET_DIR/g1/UDC
}

# This sets up the USB with whatever USB_FUNCTIONS are set to via android_usb
usb_setup_android_usb() {
    G_USB_ISERIAL=$ANDROID_USB/iSerial
    write $ANDROID_USB/enable          0
    write $ANDROID_USB/functions       ""
    write $ANDROID_USB/enable          1
    usleep 500000 # 0.5 delay to attempt to remove rndis function
    write $ANDROID_USB/enable          0
    write $ANDROID_USB/idVendor        18D1
    write $ANDROID_USB/idProduct       D001
    write $ANDROID_USB/iManufacturer   "FuriOS recovery"
    write $ANDROID_USB/iProduct        "FuriOS recovery"
    write $ANDROID_USB/iSerial         "furios-recovery"
    write $ANDROID_USB/functions       $USB_FUNCTIONS
    write $ANDROID_USB/enable          1
}

# This determines which USB setup method is going to be used
usb_setup() {
    mkdir -p /config || true
    mount -t configfs none /config || true

    if [ -d $ANDROID_USB ]; then
        usb_setup_android_usb
    elif [ -d $GADGET_DIR ]; then
        usb_setup_configfs
    fi
}

dropbear_start() {
	# Required to store hostkeys
	mkdir -p /etc/dropbear

	# Allow passwordless authentication
	sed -i 's|:x:|::|' /etc/passwd

	# Finally start dropbear
	dropbear -R -B -E
}

if [ -z $1 ]; then
	echo "No options specified"
elif [ $1 -eq 1 ]; then
	usb_setup

	USB_IFACE=notfound
	/sbin/ifconfig rndis0 $LOCAL_IP && USB_IFACE=rndis0
	if [ x$USB_IFACE = xnotfound ]; then
		/sbin/ifconfig usb0 $LOCAL_IP && USB_IFACE=usb0
	fi

	# Create /etc/udhcpd.conf file.
	echo "start 192.168.2.20" >/etc/udhcpd.conf
	echo "end 192.168.2.90" >>/etc/udhcpd.conf
	echo "lease_file /var/udhcpd.leases" >>/etc/udhcpd.conf
	echo "interface $USB_IFACE" >>/etc/udhcpd.conf
	echo "option subnet 255.255.255.0" >>/etc/udhcpd.conf

	# Be explicit about busybox so this works in a rootfs too
	echo "########################## starting dhcpd"
	udhcpd

	dropbear_start

	touch /tmp/dropbear-enabled
elif [ $1 -eq 0 ]; then
	kill -9 $(pidof udhcpd)
	kill -9 $(pidof dropbear)
	rm /tmp/dropbear-enabled
fi
