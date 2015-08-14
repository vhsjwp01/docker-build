%define __os_install_post %{nil}
%define uek %( uname -r | egrep -i uek | wc -l | awk '{print $1}' )
%define rpm_arch %( uname -p )
%define rpm_author Jason W. Plummer
%define rpm_author_email jason.plummer@ingramcontent.com
%define distro_id %( lsb_release -is )
%define distro_ver %( lsb_release -rs )
%define distro_major_ver %( echo "%{distro_ver}" | awk -F'.' '{print $1}' )

Summary: A Docker build framework tailored for git based projects
Name: icg-docker-build
Release: 4.EL%{distro_major_ver}
License: GNU
Group: Docker/Development
BuildRoot: %{_tmppath}/%{name}-root
URL: https://stash.ingramcontent.com/projects/RPM/repos/icg-docker-build/browse
Version: 1.0
BuildArch: noarch

## These BuildRequires can be found in Base
##BuildRequires: zlib, zlib-devel 
#
## This block handles Oracle Linux UEK .vs. EL BuildRequires
#%if %{uek}
#BuildRequires: kernel-uek-devel, kernel-uek-headers
#%else
#BuildRequires: kernel-devel, kernel-headers
#%endif

# These Requires can be found in Base
Requires: bind-utils
Requires: coreutils
Requires: curl
Requires: gawk
Requires: git
Requires: grep
Requires: sed

# These Requires can be found in EPEL
Requires: docker-io
Requires: jq

%define install_base /usr/local
%define install_bin_dir %{install_base}/bin
%define real_name icg-docker-build

Source0: ~/rpmbuild/SOURCES/%{real_name}.sh

%description
icg-docker-build is a helper script to build a docker image from
a git controlled SCM repo containing a Dockerfile

%install
rm -rf %{buildroot}
# Populate %{buildroot}
mkdir -p %{buildroot}%{install_bin_dir}
cp %{SOURCE0} %{buildroot}%{install_bin_dir}/%{real_name}

# Build packaging manifest
rm -rf /tmp/MANIFEST.%{name}* > /dev/null 2>&1
echo '%defattr(-,root,root)' > /tmp/MANIFEST.%{name}
chown -R root:root %{buildroot} > /dev/null 2>&1
cd %{buildroot}
find . -depth -type d -exec chmod 755 {} \;
find . -depth -type f -exec chmod 644 {} \;
for i in `find . -depth -type f | sed -e 's/\ /zzqc/g'` ; do
    filename=`echo "${i}" | sed -e 's/zzqc/\ /g'`
    eval is_exe=`file "${filename}" | egrep -i "executable" | wc -l | awk '{print $1}'`
    if [ "${is_exe}" -gt 0 ]; then
        chmod 555 "${filename}"
    fi
done
find . -type f -or -type l | sed -e 's/\ /zzqc/' -e 's/^.//' -e '/^$/d' > /tmp/MANIFEST.%{name}.tmp
for i in `awk '{print $0}' /tmp/MANIFEST.%{name}.tmp` ; do
    filename=`echo "${i}" | sed -e 's/zzqc/\ /g'`
    dir=`dirname "${filename}"`
    echo "${dir}/*"
done | sort -u >> /tmp/MANIFEST.%{name}
# Clean up what we can now and allow overwrite later
rm -f /tmp/MANIFEST.%{name}.tmp
chmod 666 /tmp/MANIFEST.%{name}

%post
chown root:docker %{install_bin_dir}/%{real_name}
chmod 750 %{install_bin_dir}/%{real_name}
if [ ! -d /usr/local/src ]; then
    mkdir -p /usr/local/src
fi
chmod 775 /usr/local/src
if [ ! -d /usr/local/src/DOCKER ]; then
    mkdir -p /usr/local/src/DOCKER
fi
chmod 770 /usr/local/src/DOCKER
chown -R root:docker /usr/local/src/DOCKER

%postun
if [ -d /usr/local/src/DOCKER ]; then
    rm -rf /usr/local/src/DOCKER
fi

%files -f /tmp/MANIFEST.%{name}

%changelog
%define today %( date +%a" "%b" "%d" "%Y )
* %{today} %{rpm_author} <%{rpm_author_email}>
- built version %{version} for %{distro_id} %{distro_ver}

