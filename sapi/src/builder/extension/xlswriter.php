<?php

use SwooleCli\Library;
use SwooleCli\Preprocessor;
use SwooleCli\Extension;

return function (Preprocessor $p) {
    $p->addExtension(
        (new Extension('xlswriter'))
            ->withHomePage('https://github.com/viest/php-ext-xlswriter')
            ->withLicense('https://github.com/viest/php-ext-xlswriter/blob/master/LICENSE', Extension::LICENSE_BSD)
            ->withPeclVersion('1.5.8')
            ->withFileHash('sha256', '202ab46a0fd6d66d21cf5e58bda67e58f05ff95109fd955ed67941466d1c833e')
            ->withOptions(' --with-xlswriter --enable-reader --with-openssl=' . OPENSSL_PREFIX)
            ->withDependentLibraries('openssl')
    );
};
