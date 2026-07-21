do_install:append:class-target() {
    if [ -d ${D}${bindir}/cpp ]; then
        mv ${D}${bindir}/cpp ${D}${bindir}/opencv_cpp
    fi
}
