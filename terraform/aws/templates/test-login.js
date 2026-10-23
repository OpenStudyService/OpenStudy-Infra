function success(r) {
    r.headersOut['Content-Type'] = 'application/json';
    r.return(200, '{"ok":true}');
}

function denied(r) {
    r.headersOut['Content-Type'] = 'application/json';
    r.return(401, '{"ok":false}');
}

function stripChallenge(r) {
    delete r.headersOut['WWW-Authenticate'];
}

export default {success, denied, stripChallenge};
