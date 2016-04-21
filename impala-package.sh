#!/bin/bash
set -e

function usage() {
	echo "Usage: impala-package.sh [-debug|-release] [-strip] path-to-impala-src path-to-install"
	echo "if no debug or release specified, release is the default"
	exit 1
}

instpath=
buildtype="debug"

while [ $# -gt 2 ]; do
	if [[ "$1" == "-debug" ]]; then
		buildtype="debug"
		shift
	elif [[ "$1" == "-release" ]]; then
		buildtype="release"
		shift
	elif [[ "$1" == "-strip" ]]; then
		do_strip="yes"
		shift
	elif [[ "$1" == "-*" ]]; then
		echo "Unknown option $1"
		usage
	else
		break
	fi
done

if [ $# -ne 2 ]; then
	usage
fi

srcpath=$1
instpath=$2

CP='cp -pva'

echo "Impala install path : $instpath"
echo "Impala build type : $buildtype"
echo "Impala source path : $srcpath"

impala_gcclib_path=$srcpath/toolchain/gcc-4.9.2/lib64
impala_home=$instpath
impala_shell=$instpath/impala-shell
mkdir -p $impala_home/bin
mkdir -p $impala_home/cloudera
mkdir -p $impala_home/lib
mkdir -p $impala_home/lib64
mkdir -p $impala_home/log
mkdir -p $impala_home/llvm-ir
mkdir -p $impala_home/sbin-debug
mkdir -p $impala_home/sbin-release
mkdir -p $impala_home/www
mkdir -p $impala_shell

if [[ "$buildtype" == "debug" ]]; then
	be_src_path=$srcpath/be/build/debug
	be_dst_path=$impala_home/sbin-debug
else
	be_src_path=$srcpath/be/build/release
	be_dst_path=$impala_home/sbin-release
fi

# HOME/sbin
# since impala 2.5.0,
# all binaries are fused into impalad, catalogd and statestred are symlnks
$CP $be_src_path/service/impalad $be_dst_path
$CP $be_src_path/service/libfesupport.so $be_dst_path
#$CP $be_src_path/catalog/catalogd $be_dst_path
#$CP $be_src_path/statestore/statestored $be_dst_path
ln -s impalad $be_dst_path/catalogd
ln -s impalad $be_dst_path/statestored

if [[ "$buildtype" == "release" ]]; then
	$CP $be_src_path/service/impalad $be_dst_path
fi

# HOME/www
$CP -r $srcpath/www/* $impala_home/www/

# HOME/llvm-ir
$CP -r $srcpath/llvm-ir/* $impala_home/llvm-ir/

# HOME/lib
$CP $srcpath/fe/target/dependency/* $impala_home/lib/
$CP $srcpath/thirdparty/hadoop-*-cdh*/share/hadoop/common/lib/junit-*.jar $impala_home/lib/
$CP $srcpath/fe/target/impala-frontend-0.1-SNAPSHOT.jar $impala_home/lib/
# HOME/lib64
$CP $srcpath/thirdparty/hadoop-*-cdh*/lib/native/libhadoop*.so* $impala_home/lib64/
$CP $srcpath/thirdparty/hadoop-*-cdh*/lib/native/libhdfs*.so* $impala_home/lib64/

# HOME/cloudera
if [ -e $srcpath/cloudera/cdh_version.properties ]; then
	$CP $srcpath/cloudera/cdh_version.properties $impala_home/cloudera
fi

# HOME/bin
# bin is empty

# impala-shell
$CP $srcpath/shell/build/impala-shell-*-cdh*/impala_shell.py $impala_shell/
$CP -r $srcpath/shell/build/impala-shell-*-cdh*/ext-py $impala_shell/
$CP -r $srcpath/shell/build/impala-shell-*-cdh*/gen-py $impala_shell/
$CP -r $srcpath/shell/build/impala-shell-*-cdh*/lib $impala_shell/

# copy other libs needed
export LD_LIBRARY_PATH=$impala_gcclib_path:$LD_LIBRARY_PATH
ldd ${be_dst_path}/impalad | grep libboost | awk '{ print $3 }' > .tmp.boost.libs.list
cat .tmp.boost.libs.list | sort -u > .tmp.boost.libs.sorted.unique
for f in `cat .tmp.boost.libs.sorted.unique`; do
	# might be a link. copy full file
	cp $f $impala_home/lib64/
	linksource=`basename $f`
	linktarget=$impala_home/lib64/`basename $f | sed 's/\.so\.[0-9]*\.[0-9]*\.[0-9]*/.so/'`
	ln -sfv $linksource $linktarget
done
rm -f .tmp.boost.libs.list .tmp.boost.libs.sorted.unique

# copy libsasl2
ldd ${be_dst_path}/impalad | grep libsasl2 | awk '{ print $3 }' > .tmp.libsasl2.list
for f in `cat .tmp.libsasl2.list`; do
	# might be a link. copy full file
	cp $f $impala_home/lib64/
	linksource=`basename $f`
	linktarget=$impala_home/lib64/`basename $f | sed 's/\.so\.[0-9]*/.so/'`
	ln -sfv $linksource $linktarget
done
rm -f .tmp.libsasl2.list

# libc++/etc
$CP $impala_gcclib_path/*.so* $impala_home/lib64/

# overwrite files in src/
$CP -r src/* $impala_home/

# strip executables
if [[ $do_strip == "yes" ]]; then
	executables=`find -executable -type f -exec file \{\} \; | grep "not stripped" | awk -F ": " '{ print $1 }'`
	for f in $executables; do
		echo -n "Stripping $f ...."
		strip --strip-unneeded $f >/dev/null 2>&1
		echo " done"
	done
fi

# link to sbin
ln -sfv `basename ${be_dst_path}` $impala_home/sbin

