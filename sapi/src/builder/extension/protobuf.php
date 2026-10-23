<?php

use SwooleCli\Preprocessor;
use SwooleCli\Extension;

return function (Preprocessor $p) {
    $p->addExtension(
        (new Extension('protobuf'))
            ->withOptions('--enable-protobuf')
            ->withPeclVersion('3.25.5')
            ->withFileHash('sha256', '5ee38f25baf789fbe71c55decbdb7ea250eae0e5f61910e3e9180794aa38d185')
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
