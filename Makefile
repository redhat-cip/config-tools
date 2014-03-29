SBINDIR=$(DESTDIR)/usr/sbin
PDIR=$(DESTDIR)/etc/puppet

all:

install:
	mkdir -p $(SBINDIR) $(PDIR)
	install -m 0755 verify-servers.sh $(SBINDIR)/
	install -m 0755 configure.sh $(SBINDIR)/
	install -m 0644 config.cpp $(PDIR)
