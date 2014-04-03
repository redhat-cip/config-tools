SBINDIR=$(DESTDIR)/usr/sbin
LIBDIR=$(DESTDIR)/usr/share/config-tools
PDIR=$(DESTDIR)/etc/puppet

all:

install:
	mkdir -p $(SBINDIR) $(PDIR) $(LIBDIR)
	install -m 0755 verify-servers.sh $(SBINDIR)/
	install -m 0755 configure.sh $(SBINDIR)/
	install -m 0755 generate.py $(LIBDIR)
