<?php
// xlswriter 3 includes a bundled minizip/zip.h that shadows PHP ext/zip's libzip/zip.h.
// Keep minizip headers private to xlswriter's own C sources.
$root = dirname(__DIR__, 2);
$config = $root . '/ext/xlswriter/config.m4';
$source = $root . '/ext/xlswriter/library/libxlsx/src/zip_io.c';
$changes = [
    $config => [
        '    PHP_ADD_INCLUDE([PHP_EXT_SRCDIR/library/libxlsx/third_party/minizip])' . "\n" => '',
    ],
    $source => [
        '#include "ioapi.h"' => '#include "../third_party/minizip/ioapi.h"',
        '#include "unzip.h"' => '#include "../third_party/minizip/unzip.h"',
    ],
];
foreach ($changes as $file => $replacements) {
    $content = file_get_contents($file);
    if ($content === false) {
        throw new RuntimeException("Cannot read {$file}");
    }
    foreach ($replacements as $from => $to) {
        if (substr_count($content, $from) !== 1) {
            throw new RuntimeException("Unexpected source layout in {$file}: {$from}");
        }
        $content = str_replace($from, $to, $content);
    }
    if (file_put_contents($file, $content) === false) {
        throw new RuntimeException("Cannot write {$file}");
    }
    echo "Patched {$file}\n";
}
