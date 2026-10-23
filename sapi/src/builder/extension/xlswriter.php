<?php

use SwooleCli\Library;
use SwooleCli\Preprocessor;
use SwooleCli\Extension;

return function (Preprocessor $p) {
    $p->addExtension(
        (new Extension('xlswriter'))
            ->withHomePage('https://github.com/viest/php-ext-xlswriter')
            ->withLicense('https://github.com/viest/php-ext-xlswriter/blob/master/LICENSE', Extension::LICENSE_BSD)
            ->withPeclVersion('3.0.0')
            ->withFileHash('sha256', 'a17986ad5ac09529513fc59b2871ca2b53eaec1c2c55cf00be60a292e85ade73')
            ->withOptions(' --with-xlswriter --with-openssl=' . OPENSSL_PREFIX)
            ->withDependentLibraries('openssl')
    );
};
