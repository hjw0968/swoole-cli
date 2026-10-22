<?php

use SwooleCli\Preprocessor;
use SwooleCli\Extension;

return function (Preprocessor $p) {
    $p->addExtension(
        (new Extension('protobuf'))
            ->withOptions('--enable-protobuf')
            ->withPeclVersion('3.21.6')
            ->withFileHash('md5', '30fd6011881fa67878805c394e425577')
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
        // PHP's genif.sh detects static extensions through phpext_* macros in headers.
        // Protobuf 3.21.6 defines the module entry but does not declare that macro.
        $cmd .= <<<'PROTOBUF_REGISTRATION'
cat > ext/protobuf/php_protobuf.h <<'PROTOBUF_STATIC_HEADER'
#ifndef PHP_PROTOBUF_STATIC_H
#define PHP_PROTOBUF_STATIC_H
#include "php.h"
extern zend_module_entry protobuf_module_entry;
#define phpext_protobuf_ptr (&protobuf_module_entry)
#endif
PROTOBUF_STATIC_HEADER
PROTOBUF_REGISTRATION;
        return $cmd;
    });
};
