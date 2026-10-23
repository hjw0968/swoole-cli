<?php

use SwooleCli\Preprocessor;
use SwooleCli\Extension;

return function (Preprocessor $p) {
    $p->addExtension(
        (new Extension('protobuf'))
            ->withOptions('--enable-protobuf')
            ->withPeclVersion('5.36.2')
            ->withFileHash('sha256', 'f0a17c67de29df0fb0e5215a381df9b155125e1ace6252dd617bf16b4194dd5b')
            ->withHomePage('https://developers.google.com/protocol-buffers')
            ->withManual('https://protobuf.dev/reference/php/php-generated/')
    );

    $p->withBeforeConfigureScript('protobuf', function (Preprocessor $p) {
        // compatible with redis
        $workdir = $p->getWorkDir();
        if ($p->isMacos()) {
            $cmd = <<<EOF
                cd {$workdir}
                sed -i '.bak' 's/arginfo_void,/arginfo_void_protobuf,/g' ext/protobuf/*.c ext/protobuf/*.h ext/protobuf/*.inc
                find ext/protobuf/ -name \*.bak | xargs rm -f
EOF;
        } else {
            $cmd = <<<EOF
                cd {$workdir}
                sed -i 's/arginfo_void,/arginfo_void_protobuf,/g' ext/protobuf/*.c ext/protobuf/*.h ext/protobuf/*.inc
EOF;
        }
        // PECL may omit php_protobuf.h, which genif.sh needs for static registration.
        // Keep the original header if supplied by the chosen Protobuf release.
        $cmd .= <<<'PROTOBUF_REGISTRATION'

if [ ! -f ext/protobuf/php_protobuf.h ]; then
    cat > ext/protobuf/php_protobuf.h <<'PROTOBUF_STATIC_HEADER'
#ifndef PHP_PROTOBUF_H
#define PHP_PROTOBUF_H
#include "php.h"
extern zend_module_entry protobuf_module_entry;
#define phpext_protobuf_ptr (&protobuf_module_entry)
#endif
PROTOBUF_STATIC_HEADER
fi
PROTOBUF_REGISTRATION;
        return $cmd;
    });
};
