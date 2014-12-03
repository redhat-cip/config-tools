SBINDIR=$(DESTDIR)/usr/sbin
LIBDIR=$(DESTDIR)/usr/share/config-tools
PDIR=$(DESTDIR)/etc/puppet
CDIR=$(DESTDIR)/etc/config-tools

all:

install:
	mkdir -p $(SBINDIR) $(PDIR) $(LIBDIR) $(CDIR)
	install -m 0755 verify-servers.sh $(SBINDIR)/
	install -m 0755 verify-steps.sh $(SBINDIR)/
	install -m 0755 configure.sh $(SBINDIR)/
	install -m 0755 generate.py $(LIBDIR)/
	install -m 0644 config.tmpl $(CDIR)/
